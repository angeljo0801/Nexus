import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/chat_message.dart';
import '../models/nexus_project.dart';
import '../models/project_integration.dart';
import '../storage/project_integration_repository.dart';
import 'github_actions_service.dart';
import 'github_auth_service.dart';
import 'local_coding_agent.dart';
import 'nexus_build_workflow.dart';
import 'project_git_service.dart';
import 'project_workspace_service.dart';

class ProjectBuildAutomationResult {
  const ProjectBuildAutomationResult({
    required this.succeeded,
    required this.attempts,
    required this.message,
    this.lastRun,
  });

  final bool succeeded;
  final int attempts;
  final String message;
  final ProjectBuildRun? lastRun;
}

class ProjectBuildService {
  ProjectBuildService._();

  static final ProjectBuildService instance = ProjectBuildService._();

  final GitHubAuthService _auth = GitHubAuthService.instance;
  final GitHubActionsService _actions = GitHubActionsService();
  final ProjectGitService _git = ProjectGitService.instance;
  final ProjectWorkspaceService _workspace = ProjectWorkspaceService.instance;
  final ProjectIntegrationRepository _integrations =
      ProjectIntegrationRepository();

  Future<void> ensureDefaultWorkflow({
    required String projectId,
    required ProjectIntegration integration,
  }) async {
    if (integration.githubWorkflow != 'nexus-build.yml') return;

    const path = '.github/workflows/nexus-build.yml';
    try {
      await _workspace.readFile(projectId, path);
      return;
    } catch (_) {}

    await _workspace.createFile(
      projectId,
      path,
      nexusBuildWorkflow,
    );
  }

  Future<ProjectBuildAutomationResult> buildAndAutoFix({
    required NexusProject project,
    required List<ChatMessage> conversation,
    void Function(String status)? onStatus,
  }) async {
    final integration = await _integrations.get(project.id);
    if (!integration.githubConfigured) {
      throw StateError(
        'Configure this project GitHub repository, branch and workflow first.',
      );
    }

    final token = await _auth.accessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Connect GitHub in Nexus Settings first.');
    }

    await ensureDefaultWorkflow(
      projectId: project.id,
      integration: integration,
    );

    await _git.ensureRepository(
      project.id,
      branch: integration.githubBranch,
    );
    await _git.configureRemote(
      projectId: project.id,
      repositoryFullName: integration.githubRepo,
    );

    final seenFailures = <String, int>{};
    ProjectBuildRun? lastRun;

    for (var cycle = 1; cycle <= integration.maxFixCycles; cycle++) {
      onStatus?.call(
        cycle == 1
            ? 'Committing and pushing project changes…'
            : 'Pushing Auto-Fix cycle $cycle…',
      );

      final commit = await _git.commitAll(
        projectId: project.id,
        branch: integration.githubBranch,
        message: cycle == 1
            ? 'Nexus project update'
            : 'Nexus Auto-Fix cycle $cycle',
      );

      await _git.push(
        projectId: project.id,
        token: token,
        branch: integration.githubBranch,
      );

      onStatus?.call('Starting GitHub Actions build…');
      final runId = await _actions.dispatchWorkflow(
        token: token,
        repositoryFullName: integration.githubRepo,
        workflow: integration.githubWorkflow,
        branch: integration.githubBranch,
      );

      onStatus?.call('GitHub Actions run #$runId is running…');
      final result = await _actions.waitForCompletion(
        token: token,
        repositoryFullName: integration.githubRepo,
        runId: runId,
        onProgress: (run) {
          onStatus?.call(
            'Build #${run.id}: '
            '${run.status}${run.conclusion.isEmpty ? '' : ' · ${run.conclusion}'}',
          );
        },
      );

      final now = DateTime.now();
      lastRun = ProjectBuildRun(
        id: 'build_${now.microsecondsSinceEpoch}',
        projectId: project.id,
        provider: 'github_actions',
        remoteRunId: result.run.id.toString(),
        status: result.run.status,
        conclusion: result.run.conclusion,
        attempt: cycle,
        commitSha:
            result.run.headSha.isNotEmpty ? result.run.headSha : commit.sha,
        summary: result.run.succeeded
            ? 'GitHub Actions build completed successfully.'
            : 'GitHub Actions build failed.',
        logExcerpt: result.logExcerpt,
        startedAt: now,
        finishedAt: DateTime.now(),
      );
      await _integrations.addBuildRun(lastRun);

      if (result.run.succeeded) {
        onStatus?.call('Build passed.');
        return ProjectBuildAutomationResult(
          succeeded: true,
          attempts: cycle,
          message:
              'GitHub Actions passed after $cycle build attempt(s).',
          lastRun: lastRun,
        );
      }

      if (!integration.autoFixEnabled) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message: 'Build failed and Auto Fix is disabled.',
          lastRun: lastRun,
        );
      }

      final fingerprint = _failureFingerprint(result.logExcerpt);
      final repeats = (seenFailures[fingerprint] ?? 0) + 1;
      seenFailures[fingerprint] = repeats;
      if (repeats >= 3) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              'Auto Fix stopped because the same build failure repeated 3 times.',
          lastRun: lastRun,
        );
      }

      if (cycle >= integration.maxFixCycles) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              'Auto Fix reached the configured limit of '
              '${integration.maxFixCycles} build cycles.',
          lastRun: lastRun,
        );
      }

      onStatus?.call(
        'Build failed. Local AI is reading the error and preparing a repair…',
      );

      final repairMessage = ChatMessage(
        id: 'autofix_${DateTime.now().microsecondsSinceEpoch}',
        projectId: project.id,
        role: 'user',
        content: _repairPrompt(
          cycle: cycle,
          logs: result.logExcerpt,
        ),
        createdAt: DateTime.now(),
      );

      final repairConversation = <ChatMessage>[
        ...conversation.takeLast(8),
        repairMessage,
      ];

      final repair = await LocalCodingAgent.instance.run(
        projectId: project.id,
        projectName: project.name,
        projectDescription: project.description,
        framework: project.framework,
        history: repairConversation,
      );

      final changed = repair.actions.any(
        (action) => const {
          'create_file',
          'write_file',
          'replace_text',
          'delete_file',
        }.contains(action),
      );

      if (!changed) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              'Build failed and the local model could not produce a concrete file repair.',
          lastRun: lastRun,
        );
      }
    }

    return ProjectBuildAutomationResult(
      succeeded: false,
      attempts: integration.maxFixCycles,
      message: 'Auto Fix stopped at its safety limit.',
      lastRun: lastRun,
    );
  }

  String _repairPrompt({
    required int cycle,
    required String logs,
  }) {
    final excerpt = logs.length <= 14000
        ? logs
        : logs.substring(logs.length - 14000);

    return '''
NEXUS AUTO-FIX BUILD FAILURE

This is repair cycle $cycle. A real GitHub Actions build failed.
Inspect the actual project files related to this error, then make the smallest
safe code/configuration changes needed to repair it.

Do not claim success because you cannot know until Nexus rebuilds after your edits.
Do not modify unrelated files.

BUILD LOG EXCERPT:
$excerpt
''';
  }

  String _failureFingerprint(String logs) {
    var normalized = logs
        .replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*'), '')
        .replaceAll(RegExp(r'\b\d+ms\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.length > 6000) {
      normalized = normalized.substring(normalized.length - 6000);
    }

    return sha256.convert(utf8.encode(normalized)).toString();
  }
}

extension _TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
