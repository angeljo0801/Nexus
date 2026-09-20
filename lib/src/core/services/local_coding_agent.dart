import 'dart:convert';

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

import '../models/chat_message.dart';
import 'agent_tool_executor.dart';
import 'local_llama_runtime.dart';
import 'project_workspace_service.dart';

class CodingAgentResult {
  const CodingAgentResult({
    required this.response,
    required this.actions,
    this.snapshotPath,
  });

  final String response;
  final List<String> actions;
  final String? snapshotPath;
}

class LocalCodingAgent {
  LocalCodingAgent._();

  static final LocalCodingAgent instance = LocalCodingAgent._();

  final AgentToolExecutor _tools = AgentToolExecutor();
  final ProjectWorkspaceService _workspace = ProjectWorkspaceService.instance;

  static final RegExp _toolBlockPattern = RegExp(
    r'''<tool(?:\s+name=["']([^"']+)["'])?\s*>(.*?)</tool>''',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _finalPattern = RegExp(
    r'<final>\s*(.*?)\s*</final>',
    dotAll: true,
    caseSensitive: false,
  );

  Future<CodingAgentResult> run({
    required String projectId,
    required String projectName,
    required String projectDescription,
    required String framework,
    required List<ChatMessage> history,
    void Function(String status)? onStatus,
  }) async {
    await _workspace.workspaceDirectory(projectId);

    final workspaceSummary = await _workspace.summary(projectId);
    final actions = <String>[];
    final verifiedChangedPaths = <String>[];
    var snapshotCreated = false;
    String? snapshotPath;
    var protocolFailures = 0;

    final recent =
        history.length > 12 ? history.sublist(history.length - 12) : history;

    final messages = <llama.ChatMessage>[
      llama.ChatMessage(
        role: 'system',
        content: _systemPrompt(
          projectName: projectName,
          projectDescription: projectDescription,
          framework: framework,
        ),
      ),
      llama.ChatMessage(
        role: 'user',
        content:
            'NEXUS WORKSPACE STATE\n$workspaceSummary\n'
            'Use tools whenever inspecting or changing project files is necessary.',
      ),
      ...recent.map(
        (message) => llama.ChatMessage(
          role: message.role == 'assistant' ? 'assistant' : 'user',
          content: message.content,
        ),
      ),
    ];

    for (var step = 0; step < 10; step++) {
      onStatus?.call(
        step == 0
            ? 'Analyzing the request and project…'
            : 'Thinking about the next project step…',
      );

      final output = await LocalLlamaRuntime.instance.generateMessages(
        messages: messages,
        maxTokens: 1600,
        temperature: 0.16,
      );

      final toolMatch = _toolBlockPattern.firstMatch(output);
      if (toolMatch == null) {
        final finalMatch = _finalPattern.firstMatch(output);
        if (finalMatch != null) {
          final response = (finalMatch.group(1) ?? '').trim();
          return CodingAgentResult(
            response: _verifiedResponse(
              response.isEmpty
                  ? 'I completed the available project work.'
                  : response,
              verifiedChangedPaths,
            ),
            actions: actions,
            snapshotPath: snapshotPath,
          );
        }

        if (_looksLikeProtocolFailure(output) && protocolFailures < 3) {
          protocolFailures++;
          messages.add(
            llama.ChatMessage(role: 'assistant', content: output),
          );
          messages.add(
            llama.ChatMessage(
              role: 'user',
              content:
                  '[NEXUS PROTOCOL RECOVERY] Your previous response was not a '
                  'valid Nexus tool call. Do not explain the formatting error. '
                  'Continue the task now using exactly one supported <tool> '
                  'call. For file creation/writes, use the tagged format with '
                  'raw <content> instead of JSON.',
            ),
          );
          continue;
        }

        final response = output.trim();
        return CodingAgentResult(
          response: _verifiedResponse(
            response.isEmpty
                ? 'I completed the available project work.'
                : response,
            verifiedChangedPaths,
          ),
          actions: actions,
          snapshotPath: snapshotPath,
        );
      }

      Map<String, dynamic> request;
      try {
        request = _parseToolRequest(toolMatch);
        protocolFailures = 0;
      } catch (error) {
        protocolFailures++;
        messages.add(
          llama.ChatMessage(role: 'assistant', content: output),
        );
        messages.add(
          llama.ChatMessage(
            role: 'user',
            content:
                '[NEXUS TOOL ERROR] The tool call could not be parsed: $error. '
                'Do not return an apology or a JSON-error message. Retry the '
                'same intended action using the tagged Nexus tool format. '
                'For example: <tool name="write_file"><path>lib/main.dart</path>'
                '<content>RAW FILE CONTENT</content></tool>.',
          ),
        );

        if (protocolFailures >= 4) {
          return CodingAgentResult(
            response:
                'Nexus could not safely decode the local model tool request '
                'after several automatic retries. No malformed tool request '
                'was executed.',
            actions: actions,
            snapshotPath: snapshotPath,
          );
        }
        continue;
      }

      final name = request['name']?.toString().trim() ?? '';
      final rawArguments = request['arguments'];
      final arguments = rawArguments is Map
          ? rawArguments.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{};

      onStatus?.call(_statusForTool(name, arguments));

      if (AgentToolExecutor.mutatingTools.contains(name) &&
          !snapshotCreated) {
        snapshotPath = await _workspace.createSnapshot(projectId);
        snapshotCreated = true;
      }

      final result = await _tools.execute(
        projectId: projectId,
        name: name,
        arguments: arguments,
      );

      if (result.success) {
        actions.add(name);
        if (result.changedWorkspace) {
          final path = arguments['path']?.toString().trim() ?? '';
          if (path.isNotEmpty && !verifiedChangedPaths.contains(path)) {
            verifiedChangedPaths.add(path);
          }
        }
      }

      messages.add(
        llama.ChatMessage(role: 'assistant', content: output),
      );
      messages.add(
        llama.ChatMessage(
          role: 'user',
          content: result.success
              ? '[NEXUS TOOL RESULT]\n'
                  'tool=$name\n'
                  '${result.text}\n'
                  'Continue. Use another tool if needed. '
                  'When the task is complete, respond with <final>summary</final>.'
              : '[NEXUS TOOL FAILURE]\n'
                  'tool=$name\n'
                  '${result.text}\n'
                  'The requested action was NOT completed. Correct the tool '
                  'arguments and retry. Do not claim this file was created or '
                  'changed until a tool result confirms success.',
        ),
      );
      );
    }

    return CodingAgentResult(
      response: _verifiedResponse(
        'I reached the 10-step safety limit for this agent run. '
        'The verified changes already made remain in the project workspace.',
        verifiedChangedPaths,
      ),
      actions: actions,
      snapshotPath: snapshotPath,
    );
  }

  String _verifiedResponse(
    String modelSummary,
    List<String> verifiedChangedPaths,
  ) {
    if (verifiedChangedPaths.isEmpty) {
      return modelSummary;
    }

    final files = verifiedChangedPaths.map((path) => '- $path').join('\n');
    return 'Nexus completed verified file changes.\n\n'
        'Verified files:\n$files\n\n'
        'The list above comes from successful write operations that Nexus '
        're-read from storage. Build/test status is reported separately.';
  }

  Map<String, dynamic> _parseToolRequest(RegExpMatch match) {
    final attributeName = match.group(1)?.trim();
    final body = match.group(2)?.trim() ?? '';

    if (attributeName != null && attributeName.isNotEmpty) {
      return <String, dynamic>{
        'name': attributeName,
        'arguments': _parseTaggedArguments(body),
      };
    }

    final normalized = _normalizeJsonCandidate(body);
    final decoded = jsonDecode(normalized);
    if (decoded is! Map) {
      throw const FormatException('Tool request must be a JSON object.');
    }

    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Map<String, dynamic> _parseTaggedArguments(String body) {
    final arguments = <String, dynamic>{};
    const keys = <String>[
      'path',
      'content',
      'query',
      'old_text',
      'new_text',
      'all',
    ];

    for (final key in keys) {
      final pattern = RegExp(
        '<$key>\\s*(.*?)\\s*</$key>',
        dotAll: true,
        caseSensitive: false,
      );
      final match = pattern.firstMatch(body);
      if (match == null) continue;

      final value = match.group(1) ?? '';
      if (key == 'all') {
        arguments[key] = value.trim().toLowerCase() == 'true';
      } else if (key == 'content' ||
          key == 'old_text' ||
          key == 'new_text') {
        arguments[key] = _unwrapCdata(value);
      } else {
        arguments[key] = value.trim();
      }
    }

    return arguments;
  }

  String _unwrapCdata(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('<![CDATA[') && trimmed.endsWith(']]>')) {
      return trimmed.substring(9, trimmed.length - 3);
    }
    return value;
  }

  String _normalizeJsonCandidate(String value) {
    var candidate = value.trim();

    candidate = candidate
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll(RegExp(r',\s*([}\]])'), r'$1');

    return candidate.trim();
  }

  bool _looksLikeProtocolFailure(String output) {
    final lower = output.toLowerCase();
    return lower.contains('error parsing') ||
        lower.contains('invalid json') ||
        lower.contains('json input') ||
        lower.contains('json format') ||
        lower.contains('tool error') ||
        lower.contains('parse the json');
  }

  String _statusForTool(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final path = arguments['path']?.toString().trim() ?? '';
    return switch (name) {
      'workspace_summary' => 'Inspecting project structure…',
      'list_files' => 'Listing project files…',
      'read_file' =>
        path.isEmpty ? 'Reading project file…' : 'Reading $path…',
      'search_code' => 'Searching project code…',
      'git_status' => 'Checking local Git status…',
      'git_diff' => 'Reviewing local changes…',
      'create_file' =>
        path.isEmpty ? 'Creating project file…' : 'Creating $path…',
      'write_file' =>
        path.isEmpty ? 'Writing project file…' : 'Writing $path…',
      'replace_text' =>
        path.isEmpty ? 'Editing project file…' : 'Editing $path…',
      'delete_file' =>
        path.isEmpty ? 'Deleting project file…' : 'Deleting $path…',
      _ => 'Running Nexus project tool…',
    };
  }

  String _systemPrompt({
    required String projectName,
    required String projectDescription,
    required String framework,
  }) {
    return '''
You are Nexus, a local autonomous coding agent.

PROJECT
Name: $projectName
Framework: $framework
Description: $projectDescription

You have real file tools for this project's sandboxed workspace. Never claim
you inspected or changed a file unless you used a tool and received a
successful result. Never invent file contents.

TOOL PROTOCOL
When you need a tool, output exactly one tool call.

PREFERRED FORMAT, especially when source code is involved:
<tool name="write_file">
<path>lib/main.dart</path>
<content>
RAW FILE CONTENT HERE
</content>
</tool>

For focused replacements:
<tool name="replace_text">
<path>relative/path</path>
<old_text>exact old text</old_text>
<new_text>replacement text</new_text>
<all>false</all>
</tool>

Simple tools may also use JSON:
<tool>{"name":"read_file","arguments":{"path":"lib/main.dart"}}</tool>

IMPORTANT:
- Never put multiline source code inside JSON for create_file or write_file.
- Use the tagged format with raw <content> for source files.
- Do not wrap tool calls in Markdown code fences.
- Output exactly one tool call with no explanation before or after it.
- If a tool request formatting attempt fails, retry the intended tool call
  directly. Never answer the user with a JSON parsing error.
- Never claim a file was created or changed after a failed tool result.
- Nexus independently verifies successful file writes before reporting them.

Available tools:
1. workspace_summary {}
2. list_files {"path":"."}
3. read_file {"path":"relative/path"}
4. search_code {"query":"text"}
5. git_status {}
6. git_diff {}
7. create_file with <path> and <content>
8. write_file with <path> and <content>
9. replace_text with <path>, <old_text>, <new_text>, <all>
10. delete_file {"path":"relative/path"}

Rules:
- All paths must be relative to the Nexus project workspace.
- Inspect relevant existing files before editing them.
- Prefer replace_text for focused edits and write_file for complete
  rewrites or new generated files.
- Do not delete files unless the user's task clearly requires it.
- Do not attempt to access paths outside the project.
- Git status/diff are real local tools. Commits, push and GitHub Actions are
  orchestrated by Nexus outside the model tool loop so credentials never
  enter the prompt.
- Do not pretend a build or test ran until Nexus supplies an actual result.
- If a task requires unavailable execution, finish the code changes you can
  safely make and clearly state what still needs verification.
- When finished, return:
<final>A concise explanation of what you changed, which files matter, and
anything still needing build/test verification.</final>
''';
  }
}
