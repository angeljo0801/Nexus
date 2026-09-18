import 'dart:convert';

import 'project_git_service.dart';
import 'project_workspace_service.dart';

class AgentToolResult {
  const AgentToolResult({
    required this.text,
    this.changedWorkspace = false,
  });

  final String text;
  final bool changedWorkspace;
}

class AgentToolExecutor {
  AgentToolExecutor({
    ProjectWorkspaceService? workspace,
  }) : _workspace = workspace ?? ProjectWorkspaceService.instance;

  final ProjectWorkspaceService _workspace;
  final ProjectGitService _git = ProjectGitService.instance;

  static const Set<String> mutatingTools = {
    'create_file',
    'write_file',
    'replace_text',
    'delete_file',
  };

  Future<AgentToolResult> execute({
    required String projectId,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    try {
      switch (name) {
        case 'list_files':
          final files = await _workspace.listFiles(
            projectId,
            path: _string(arguments, 'path', fallback: '.'),
          );
          return AgentToolResult(
            text: jsonEncode({'files': files}),
          );

        case 'read_file':
          final path = _requiredString(arguments, 'path');
          final content = await _workspace.readFile(projectId, path);
          return AgentToolResult(
            text: jsonEncode({'path': path, 'content': content}),
          );

        case 'search_code':
          final query = _requiredString(arguments, 'query');
          final results = await _workspace.searchCode(projectId, query);
          return AgentToolResult(
            text: jsonEncode({'query': query, 'matches': results}),
          );

        case 'create_file':
          final path = _requiredString(arguments, 'path');
          final content = _string(arguments, 'content');
          await _workspace.createFile(projectId, path, content);
          return AgentToolResult(
            text: jsonEncode({'created': path}),
            changedWorkspace: true,
          );

        case 'write_file':
          final path = _requiredString(arguments, 'path');
          final content = _string(arguments, 'content');
          await _workspace.writeFile(projectId, path, content);
          return AgentToolResult(
            text: jsonEncode({'written': path}),
            changedWorkspace: true,
          );

        case 'replace_text':
          final path = _requiredString(arguments, 'path');
          final oldText = _requiredString(arguments, 'old_text');
          final newText = _string(arguments, 'new_text');
          final all = arguments['all'] == true;
          final count = await _workspace.replaceText(
            projectId,
            path,
            oldText: oldText,
            newText: newText,
            all: all,
          );
          return AgentToolResult(
            text: jsonEncode({'path': path, 'replacements': count}),
            changedWorkspace: true,
          );

        case 'delete_file':
          final path = _requiredString(arguments, 'path');
          await _workspace.deleteFile(projectId, path);
          return AgentToolResult(
            text: jsonEncode({'deleted': path}),
            changedWorkspace: true,
          );

        case 'workspace_summary':
          final summary = await _workspace.summary(projectId);
          return AgentToolResult(
            text: jsonEncode({'summary': summary}),
          );

        case 'git_status':
          final status = await _git.status(projectId);
          return AgentToolResult(
            text: jsonEncode({
              'branch': status.branch,
              'clean': status.clean,
              'changed_file_count': status.changedFileCount,
              'added': status.added,
              'changed': status.changed,
              'modified': status.modified,
              'missing': status.missing,
              'removed': status.removed,
              'untracked': status.untracked,
            }),
          );

        case 'git_diff':
          final diff = await _git.diff(projectId);
          return AgentToolResult(
            text: jsonEncode({
              'diff': diff,
            }),
          );

        default:
          return AgentToolResult(
            text: jsonEncode({
              'error': 'Unknown tool',
              'tool': name,
            }),
          );
      }
    } catch (error) {
      return AgentToolResult(
        text: jsonEncode({
          'error': error.toString(),
          'tool': name,
        }),
      );
    }
  }

  static String _requiredString(
    Map<String, dynamic> arguments,
    String key,
  ) {
    final value = arguments[key]?.toString() ?? '';
    if (value.trim().isEmpty) {
      throw ArgumentError('Missing required argument: $key');
    }
    return value;
  }

  static String _string(
    Map<String, dynamic> arguments,
    String key, {
    String fallback = '',
  }) {
    return arguments[key]?.toString() ?? fallback;
  }
}
