import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/chat_message.dart';
import '../models/nexus_preferences.dart';
import '../models/nexus_project.dart';
import '../models/project_integration.dart';
import '../storage/project_integration_repository.dart';
import 'github_actions_service.dart';
import 'github_auth_service.dart';
import 'hybrid_execution_router.dart';
import 'local_coding_agent.dart';
import 'nexus_build_workflow.dart';
import 'phone_build_runner.dart';
import 'project_git_service.dart';
import 'project_workspace_service.dart';

class ProjectBuildAutomationResult {
  const ProjectBuildAutomationResult({
    required this.succeeded,
    required this.attempts,
    required this.message,
    this.lastRun,
    this.resolvedTarget,
  });

  final bool succeeded;
  final int attempts;
  final String message;
  final ProjectBuildRun? lastRun;
  final BuildTarget? resolvedTarget;
}

class ProjectBuildService {
  ProjectBuildService._();

  static final ProjectBuildService instance = ProjectBuildService._();

  final GitHubAuthService _auth = GitHubAuthService.instance;
  final GitHubActionsService _actions = GitHubActionsService();
  final ProjectGitService _git = ProjectGitService.instance;
  final ProjectWorkspaceService _workspace = ProjectWorkspaceService.instance;
  final PhoneBuildRunner _phoneRunner = PhoneBuildRunner.instance;
  final ProjectIntegrationRepository _integrations =
      ProjectIntegrationRepository();
  final HybridExecutionRouter _router = HybridExecutionRouter.instance;

  Future<HybridExecutionDecision> previewRoute(String projectId) async {
    final integration = await _integrations.get(projectId);
    return _router.resolve(integration: integration);
  }

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
    final decision = await _router.resolve(integration: integration);
    onStatus?.call(decision.reason);

    if (!decision.available || decision.resolved == null) {
      await _git.ensureRepository(
        project.id,
        branch: integration.githubBranch,
      );
      final checkpoint = await _git.commitAll(
        projectId: project.id,
        branch: integration.githubBranch,
        message: 'Nexus local checkpoint',
      );

      return ProjectBuildAutomationResult(
        succeeded: false,
        attempts: 0,
        message: checkpoint.created
            ? 'Local checkpoint ${checkpoint.sha.substring(0, 7)} created. '
                '${decision.reason}'
            : 'Project is preserved locally. ${decision.reason}',
        resolvedTarget: decision.resolved,
      );
    }

    switch (decision.resolved!) {
      case BuildTarget.github:
        return _buildWithGitHub(
          project: project,
          conversation: conversation,
          integration: integration,
          onStatus: onStatus,
        );

      case BuildTarget.pc:
        return const ProjectBuildAutomationResult(
          succeeded: false,
          attempts: 0,
          message:
              'PC local build was selected, but the Nexus Bridge build '
              'executor is not connected in this version yet.',
          resolvedTarget: BuildTarget.pc,
        );

      case BuildTarget.phone:
        return _buildOnPhone(
          project: project,
          conversation: conversation,
          integration: integration,
          onStatus: onStatus,
        );

      case BuildTarget.automatic:
        throw StateError('Automatic build target must resolve before execution.');
    }
  }

  Future<ProjectBuildAutomationResult> _buildOnPhone({
    required NexusProject project,
    required List<ChatMessage> conversation,
    required ProjectIntegration integration,
    void Function(String status)? onStatus,
  }) async {
    final seenFailures = <String, int>{};
    ProjectBuildRun? lastRun;

    await _git.ensureRepository(
      project.id,
      branch: integration.githubBranch,
    );

    for (var cycle = 1; cycle <= integration.maxFixCycles; cycle++) {
      onStatus?.call(
        cycle == 1
            ? 'Creating local checkpoint before phone build…'
            : 'Creating local Auto-Fix checkpoint $cycle…',
      );

      final commit = await _git.commitAll(
        projectId: project.id,
        branch: integration.githubBranch,
        message: cycle == 1
            ? 'Nexus phone build'
            : 'Nexus phone Auto-Fix cycle $cycle',
      );

      final startedAt = DateTime.now();
      final result = await _phoneRunner.build(
        projectId: project.id,
        onStatus: onStatus,
      );

      final logExcerpt = _tail(result.log, 24000);
      final now = DateTime.now();
      lastRun = ProjectBuildRun(
        id: 'phone_${now.microsecondsSinceEpoch}',
        projectId: project.id,
        provider: 'phone_termux',
        remoteRunId: '',
        status: 'completed',
        conclusion: result.success ? 'success' : 'failure',
        attempt: cycle,
        commitSha: commit.sha,
        summary: result.success && result.artifactPath != null
            ? '${result.message} APK: ${result.artifactPath}'
            : result.message,
        logExcerpt: logExcerpt,
        startedAt: startedAt,
        finishedAt: now,
      );
      await _integrations.addBuildRun(lastRun);

      if (result.success) {
        onStatus?.call('Phone-local build passed.');
        return ProjectBuildAutomationResult(
          succeeded: true,
          attempts: cycle,
          message:
              'Phone-local Termux build passed after $cycle attempt(s).'
              '${result.artifactPath == null ? '' : ' APK saved locally.'}',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }

      if (!integration.autoFixEnabled) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message: '${result.message} Auto Fix is disabled.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }

      if (result.log.trim().isEmpty) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              '${result.message} No compiler log was returned, so Nexus did '
              'not ask the coding model to guess at a repair.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }

      final fingerprint = _failureFingerprint(result.log);
      final repeats = (seenFailures[fingerprint] ?? 0) + 1;
      seenFailures[fingerprint] = repeats;
      if (repeats >= 3) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              'Phone Auto Fix stopped because the same build failure repeated 3 times.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }

      if (cycle >= integration.maxFixCycles) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message:
              'Phone Auto Fix reached the configured limit of '
              '${integration.maxFixCycles} build cycles.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }

      onStatus?.call(
        'Phone build failed. Local AI is reading the compiler log…',
      );

      final repairMessage = ChatMessage(
        id: 'phone_autofix_${DateTime.now().microsecondsSinceEpoch}',
        projectId: project.id,
        role: 'user',
        content: _phoneRepairPrompt(
          cycle: cycle,
          logs: result.log,
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
        onStatus: onStatus,
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
              'The phone build failed and the local model did not produce a concrete file repair.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.phone,
        );
      }
    }

    return ProjectBuildAutomationResult(
      succeeded: false,
      attempts: integration.maxFixCycles,
      message: 'Phone Auto Fix stopped at its safety limit.',
      lastRun: lastRun,
      resolvedTarget: BuildTarget.phone,
    );
  }

  Future<ProjectBuildAutomationResult> _buildWithGitHub({
    required NexusProject project,
    required List<ChatMessage> conversation,
    required ProjectIntegration integration,
    void Function(String status)? onStatus,
  }) async {
    if (!integration.githubConfigured) {
      throw StateError(
        'Configure this project GitHub repository, branch and workflow first.',
      );
    }
    if (!integration.githubSyncAllowed) {
      return const ProjectBuildAutomationResult(
        succeeded: false,
        attempts: 0,
        message:
            'GitHub build was blocked because this project is set to Local Only.',
        resolvedTarget: BuildTarget.github,
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
          resolvedTarget: BuildTarget.github,
        );
      }

      if (!integration.autoFixEnabled) {
        return ProjectBuildAutomationResult(
          succeeded: false,
          attempts: cycle,
          message: 'Build failed and Auto Fix is disabled.',
          lastRun: lastRun,
          resolvedTarget: BuildTarget.github,
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
          resolvedTarget: BuildTarget.github,
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
          resolvedTarget: BuildTarget.github,
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
        onStatus: onStatus,
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
          resolvedTarget: BuildTarget.github,
        );
      }
    }

    return ProjectBuildAutomationResult(
      succeeded: false,
      attempts: integration.maxFixCycles,
      message: 'Auto Fix stopped at its safety limit.',
      lastRun: lastRun,
      resolvedTarget: BuildTarget.github,
    );
  }

  String _phoneRepairPrompt({
    required int cycle,
    required String logs,
  }) {
    final excerpt = _tail(logs, 14000);
    return '''
NEXUS PHONE AUTO-FIX BUILD FAILURE

This is repair cycle $cycle. A real Flutter build running locally in Termux
on this Android phone failed.

Inspect the actual project files related to the compiler/test error and make
the smallest safe code or configuration change needed to repair it.

Do not modify Termux-specific temporary build patches because Nexus applies
those only inside the temporary build copy. Do not claim success until Nexus
runs the next real phone build.

PHONE BUILD LOG EXCERPT:
$excerpt
''';
  }

  String _tail(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return value.substring(value.length - maxChars);
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
