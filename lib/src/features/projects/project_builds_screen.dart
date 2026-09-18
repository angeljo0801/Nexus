import 'package:flutter/material.dart';

import '../../core/models/nexus_project.dart';
import '../../core/models/project_integration.dart';
import '../../core/services/github_auth_service.dart';
import '../../core/services/project_build_service.dart';
import '../../core/services/project_git_service.dart';
import '../../core/storage/chat_repository.dart';
import '../../core/storage/project_integration_repository.dart';

class ProjectBuildsScreen extends StatefulWidget {
  const ProjectBuildsScreen({
    super.key,
    required this.project,
  });

  final NexusProject project;

  @override
  State<ProjectBuildsScreen> createState() => _ProjectBuildsScreenState();
}

class _ProjectBuildsScreenState extends State<ProjectBuildsScreen> {
  final ProjectIntegrationRepository integrations =
      ProjectIntegrationRepository();
  final ProjectGitService git = ProjectGitService.instance;
  final ChatRepository chats = ChatRepository();

  final repoController = TextEditingController();
  final branchController = TextEditingController();
  final workflowController = TextEditingController();

  ProjectIntegration? integration;
  List<ProjectBuildRun> runs = const [];
  bool loading = true;
  bool building = false;
  bool gitBusy = false;
  bool autoFix = true;
  int maxCycles = 3;
  String buildStatus = '';
  String gitSummary = 'Not checked';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    repoController.dispose();
    branchController.dispose();
    workflowController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final config = await integrations.get(widget.project.id);
    final history = await integrations.listBuildRuns(widget.project.id);
    if (!mounted) return;

    repoController.text = config.githubRepo;
    branchController.text = config.githubBranch;
    workflowController.text = config.githubWorkflow;

    setState(() {
      integration = config;
      runs = history;
      autoFix = config.autoFixEnabled;
      maxCycles = config.maxFixCycles;
      loading = false;
    });

    await refreshGit();
  }

  Future<ProjectIntegration> saveConfig({bool showMessage = true}) async {
    final current = integration ??
        ProjectIntegration(
          projectId: widget.project.id,
          updatedAt: DateTime.now(),
        );

    final updated = current.copyWith(
      githubRepo: repoController.text.trim(),
      githubBranch: branchController.text.trim().isEmpty
          ? 'main'
          : branchController.text.trim(),
      githubWorkflow: workflowController.text.trim().isEmpty
          ? 'nexus-build.yml'
          : workflowController.text.trim(),
      autoFixEnabled: autoFix,
      maxFixCycles: maxCycles,
    );

    await integrations.save(updated);
    if (!mounted) return updated;

    setState(() => integration = updated);
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project build configuration saved.')),
      );
    }
    return updated;
  }

  Future<void> refreshGit() async {
    setState(() => gitBusy = true);
    try {
      final status = await git.status(widget.project.id);
      if (!mounted) return;
      setState(() {
        gitSummary = status.clean
            ? 'Clean · ${status.branch}'
            : '${status.changedFileCount} changed file(s) · ${status.branch}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => gitSummary = 'Git error: $error');
    } finally {
      if (mounted) setState(() => gitBusy = false);
    }
  }

  Future<void> showDiff() async {
    try {
      final diff = await git.diff(widget.project.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 900,
              maxHeight: 720,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.difference_outlined),
                  title: const Text('Git diff'),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      diff.trim().isEmpty
                          ? 'No uncommitted text changes.'
                          : diff,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read Git diff: $error')),
      );
    }
  }

  Future<void> buildNow() async {
    if (building) return;

    final config = await saveConfig(showMessage: false);
    if (!config.githubConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter GitHub repository, branch and workflow first.'),
        ),
      );
      return;
    }

    final account = await GitHubAuthService.instance.account();
    if (account == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect GitHub from Nexus Settings first.'),
        ),
      );
      return;
    }

    setState(() {
      building = true;
      buildStatus = 'Preparing project build…';
    });

    try {
      final conversation = await chats.listMessages(widget.project.id);
      final result = await ProjectBuildService.instance.buildAndAutoFix(
        project: widget.project,
        conversation: conversation,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => buildStatus = status);
        },
      );

      final history = await integrations.listBuildRuns(widget.project.id);
      if (!mounted) return;
      setState(() {
        runs = history;
        buildStatus = result.message;
      });

      await refreshGit();
    } catch (error) {
      if (!mounted) return;
      setState(() => buildStatus = 'Build error: $error');
    } finally {
      if (mounted) setState(() => building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Git & Builds',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Nexus commits the local workspace, pushes it to the configured '
          'GitHub repository, runs GitHub Actions, reads failed logs and can '
          'repair/retry automatically.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: repoController,
                  enabled: !building,
                  decoration: const InputDecoration(
                    labelText: 'GitHub repository',
                    hintText: 'owner/repository',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: branchController,
                  enabled: !building,
                  decoration: const InputDecoration(
                    labelText: 'Branch',
                    hintText: 'main',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: workflowController,
                  enabled: !building,
                  decoration: const InputDecoration(
                    labelText: 'Workflow file',
                    hintText: 'nexus-build.yml',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: autoFix,
                  onChanged:
                      building ? null : (value) => setState(() => autoFix = value),
                  title: const Text('Auto Fix'),
                  subtitle: const Text(
                    'On failure, send real build logs to the selected local '
                    'model, edit the project and rebuild.',
                  ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: maxCycles,
                  decoration: const InputDecoration(
                    labelText: 'Maximum build / repair cycles',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    10,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1}'),
                    ),
                  ),
                  onChanged: building
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => maxCycles = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: building ? null : () => saveConfig(),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Local Git'),
                subtitle: Text(gitSummary),
                trailing: gitBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: refreshGit,
                        icon: const Icon(Icons.refresh),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.difference_outlined),
                title: const Text('View uncommitted diff'),
                onTap: gitBusy ? null : showDiff,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: building ? null : buildNow,
          icon: building
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(building ? 'Building…' : 'Build on GitHub'),
        ),
        if (buildStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(buildStatus),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Build history',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (runs.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('No builds yet'),
              subtitle: Text(
                'The first real GitHub Actions run will appear here.',
              ),
            ),
          )
        else
          ...runs.map(
            (run) => Card(
              child: ExpansionTile(
                leading: Icon(
                  run.succeeded
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                title: Text(
                  'Attempt ${run.attempt} · '
                  '${run.conclusion.isEmpty ? run.status : run.conclusion}',
                ),
                subtitle: Text(
                  run.remoteRunId.isEmpty
                      ? run.commitSha
                      : 'GitHub run #${run.remoteRunId}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(run.summary),
                  ),
                  if (run.logExcerpt.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          run.logExcerpt,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
