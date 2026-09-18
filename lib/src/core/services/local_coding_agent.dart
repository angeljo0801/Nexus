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

  static final RegExp _toolPattern = RegExp(
    r'<tool>\s*(\{.*?\})\s*</tool>',
    dotAll: true,
  );

  static final RegExp _finalPattern = RegExp(
    r'<final>\s*(.*?)\s*</final>',
    dotAll: true,
  );

  Future<CodingAgentResult> run({
    required String projectId,
    required String projectName,
    required String projectDescription,
    required String framework,
    required List<ChatMessage> history,
  }) async {
    await _workspace.workspaceDirectory(projectId);

    final workspaceSummary = await _workspace.summary(projectId);
    final actions = <String>[];
    var snapshotCreated = false;
    String? snapshotPath;

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
      final output = await LocalLlamaRuntime.instance.generateMessages(
        messages: messages,
        maxTokens: 1400,
        temperature: 0.18,
      );

      final toolMatch = _toolPattern.firstMatch(output);
      if (toolMatch == null) {
        final finalMatch = _finalPattern.firstMatch(output);
        final response =
            (finalMatch?.group(1) ?? output).trim();
        return CodingAgentResult(
          response: response.isEmpty
              ? 'I completed the available project work.'
              : response,
          actions: actions,
          snapshotPath: snapshotPath,
        );
      }

      Map<String, dynamic> request;
      try {
        final decoded = jsonDecode(toolMatch.group(1)!);
        if (decoded is! Map) {
          throw const FormatException('Tool request must be an object.');
        }
        request = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } catch (error) {
        messages.add(
          llama.ChatMessage(role: 'assistant', content: output),
        );
        messages.add(
          llama.ChatMessage(
            role: 'user',
            content:
                '[NEXUS TOOL ERROR] Invalid tool JSON: $error. '
                'Return exactly one valid <tool>{...}</tool> request or a <final> response.',
          ),
        );
        continue;
      }

      final name = request['name']?.toString().trim() ?? '';
      final rawArguments = request['arguments'];
      final arguments = rawArguments is Map
          ? rawArguments.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{};

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

      actions.add(name);
      messages.add(
        llama.ChatMessage(role: 'assistant', content: output),
      );
      messages.add(
        llama.ChatMessage(
          role: 'user',
          content:
              '[NEXUS TOOL RESULT]\n'
              'tool=$name\n'
              '${result.text}\n'
              'Continue. Use another tool if needed. '
              'When the task is complete, respond with <final>summary</final>.',
        ),
      );
    }

    return CodingAgentResult(
      response:
          'I reached the 10-step safety limit for this agent run. '
          'The changes already made remain in the project workspace. '
          'Ask me to continue and I will inspect the current state first.',
      actions: actions,
      snapshotPath: snapshotPath,
    );
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

You have real file tools for this project's sandboxed workspace. Never claim you inspected or changed a file unless you used a tool and received a successful result. Never invent file contents.

TOOL PROTOCOL
When you need a tool, output exactly one tool call in this form:
<tool>{"name":"tool_name","arguments":{"key":"value"}}</tool>

Available tools:
1. workspace_summary {}
2. list_files {"path":"."}
3. read_file {"path":"relative/path"}
4. search_code {"query":"text"}
5. git_status {}
6. git_diff {}
7. create_file {"path":"relative/path","content":"full content"}
8. write_file {"path":"relative/path","content":"full content"}
9. replace_text {"path":"relative/path","old_text":"exact text","new_text":"replacement","all":false}
10. delete_file {"path":"relative/path"}

Rules:
- All paths must be relative to the Nexus project workspace.
- Inspect relevant existing files before editing them.
- Prefer replace_text for focused edits and write_file for complete rewrites/new generated files.
- Do not delete files unless the user's task clearly requires it.
- Do not attempt to access paths outside the project.
- Git status/diff are real local tools. Commits, push and GitHub Actions are orchestrated by Nexus outside the model tool loop so credentials never enter the prompt. Do not pretend a build or test ran until Nexus supplies an actual build result.
- If a task requires unavailable execution, finish the code changes you can safely make and clearly state what still needs verification.
- When finished, return:
<final>A concise explanation of what you changed, which files matter, and anything still needing build/test verification.</final>
''';
  }
}
