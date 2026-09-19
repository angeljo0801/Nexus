import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/nexus_preferences.dart';
import '../../core/models/nexus_project.dart';
import '../../core/models/project_integration.dart';
import '../../core/services/background_work_coordinator.dart';
import '../../core/services/phone_build_runner.dart';
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
  final PhoneBuildRunner phoneRunner = PhoneBuildRunner.instance;
  final NexusBackgroundWorkCoordinator background =
      NexusBackgroundWorkCoordinator.instance;

  final repoController = TextEditingController();
  final branchController = TextEditingController();
  final workflowController = TextEditingController();

  ProjectIntegration? integration;
  List<ProjectBuildRun> runs = const [];
  PhoneBuildAvailability? phoneAvailability;

  bool loading = true;
  bool building = false;
  bool gitBusy = false;
  bool phoneRunnerBusy = false;
  bool autoFix = true;
  int maxCycles = 3;

  BuildTarget buildTarget = BuildTarget.automatic;
  SyncTarget syncTarget = SyncTarget.automatic;

  String buildStatus = '';
  String gitSummary = 'Not checked';
  String routeSummary = 'Resolving…';
  String phoneRunnerStatus = '';

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
      buildTarget = config.buildTarget;
      syncTarget = config.syncTarget;
      loading = false;
    });

    await refreshGit();
    await refreshPhoneRunner();
    await refreshRoute();
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
      buildTarget: buildTarget,
      syncTarget: syncTarget,
      autoFixEnabled: autoFix,
      maxFixCycles: maxCycles,
    );

    await integrations.save(updated);
    if (!mounted) return updated;

    setState(() => integration = updated);
    await refreshRoute();

    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project build configuration saved.')),
      );
    }
    return updated;
  }

  Future<void> refreshGit() async {
    if (mounted) setState(() => gitBusy = true);
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

  Future<void> refreshPhoneRunner() async {
    try {
      final value = await phoneRunner.availability();
      if (!mounted) return;
      setState(() => phoneAvailability = value);
    } catch (error) {
      if (!mounted) return;
      setState(() => phoneRunnerStatus = 'Phone runner status error: $error');
    }
  }

  Future<void> refreshRoute() async {
    try {
      final decision =
          await ProjectBuildService.instance.previewRoute(widget.project.id);
      if (!mounted) return;
      setState(() {
        routeSummary = decision.available
            ? '${decision.resolved?.label ?? 'Unknown'} · ${decision.reason}'
            : decision.reason;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => routeSummary = 'Route error: $error');
    }
  }

  Future<void> requestPhoneRunnerPermission() async {
    if (phoneRunnerBusy) return;
    setState(() {
      phoneRunnerBusy = true;
      phoneRunnerStatus = 'Requesting Termux command permission…';
    });

    try {
      final granted = await phoneRunner.requestRunCommandPermission();
      if (!mounted) return;
      setState(() {
        phoneRunnerStatus = granted
            ? 'Termux command permission granted.'
            : 'Permission was not granted.';
      });
      await refreshPhoneRunner();
      await refreshRoute();
    } catch (error) {
      if (!mounted) return;
      setState(() => phoneRunnerStatus = 'Permission error: $error');
    } finally {
      if (mounted) setState(() => phoneRunnerBusy = false);
    }
  }

  Future<void> showExternalAppsSetup() async {
    const command =
        "mkdir -p ~/.termux; touch ~/.termux/termux.properties; "
        "grep -q 'allow-external-apps=true' ~/.termux/termux.properties "
        "|| echo 'allow-external-apps=true' >> ~/.termux/termux.properties; "
        "termux-reload-settings";

    await Clipboard.setData(const ClipboardData(text: command));
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('One-time Termux setup'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'The setup command was copied to your clipboard. Open Termux, '
            'paste it, and press Enter. This enables external apps only when '
            'they also hold the Termux RUN_COMMAND permission.\n\n'
            'After running it, return to Nexus and tap Verify or Install '
            'Flutter ARM64.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              phoneRunner.openTermux();
            },
            child: const Text('Open Termux'),
          ),
        ],
      ),
    );
  }

  Future<void> installPhoneRunner() async {
    if (phoneRunnerBusy) return;
    setState(() {
      phoneRunnerBusy = true;
      phoneRunnerStatus = 'Starting Phone Runner installation…';
    });

    String? taskId;
    try {
      taskId = await background.begin(
        title: 'Nexus · Phone Runner',
        status: 'Installing Flutter ARM64…',
      );
      final result = await phoneRunner.installToolchain(
        onStatus: (status) {
          if (taskId != null) {
            background.update(taskId!, status: status);
          }
          if (!mounted) return;
          setState(() => phoneRunnerStatus = status);
        },
      );
      if (mounted) {
        setState(() => phoneRunnerStatus = result.message);
      }
      await refreshPhoneRunner();
      await refreshRoute();
    } catch (error) {
      if (mounted) {
        setState(() => phoneRunnerStatus = 'Installation error: $error');
      }
    } finally {
      if (taskId != null) {
        await background.end(taskId);
      }
      if (mounted) setState(() => phoneRunnerBusy = false);
    }
  }

  Future<void> verifyPhoneRunner() async {
    if (phoneRunnerBusy) return;
    setState(() {
      phoneRunnerBusy = true;
      phoneRunnerStatus = 'Verifying Phone Runner…';
    });

    String? taskId;
    try {
      taskId = await background.begin(
        title: 'Nexus · Phone Runner',
        status: 'Verifying Flutter ARM64 toolchain…',
      );
      final result = await phoneRunner.verify(
        onStatus: (status) {
          if (taskId != null) {
            background.update(taskId!, status: status);
          }
          if (!mounted) return;
          setState(() => phoneRunnerStatus = status);
        },
      );
      if (mounted) {
        setState(() => phoneRunnerStatus = result.message);
      }
      await refreshPhoneRunner();
      await refreshRoute();
    } catch (error) {
      if (mounted) {
        setState(() => phoneRunnerStatus = 'Verification error: $error');
      }
    } finally {
      if (taskId != null) {
        await background.end(taskId);
      }
      if (mounted) setState(() => phoneRunnerBusy = false);
    }
  }

  Future<void> showDiff() async {
    try {
      final diff = await git.diff(widget.project.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.difference_outlined),
                  title: const Text('Git diff'),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
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
    await saveConfig(showMessage: false);
    if (!mounted) return;

    setState(() {
      building = true;
      buildStatus = 'Preparing project build…';
    });

    String? taskId;
    try {
      taskId = await background.begin(
        title: 'Nexus · ${widget.project.name}',
        status: 'Preparing project build…',
      );
      final conversation = await chats.listMessages(widget.project.id);
      final result = await ProjectBuildService.instance.buildAndAutoFix(
        project: widget.project,
        conversation: conversation,
        onStatus: (status) {
          if (taskId != null) {
            background.update(taskId!, status: status);
          }
          if (!mounted) return;
          setState(() => buildStatus = status);
        },
      );

      final history = await integrations.listBuildRuns(widget.project.id);
      if (mounted) {
        setState(() {
          runs = history;
          buildStatus = result.message;
        });
      }

      await refreshGit();
      await refreshRoute();
    } catch (error) {
      if (mounted) {
        setState(() => buildStatus = 'Build error: $error');
      }
    } finally {
      if (taskId != null) {
        await background.end(taskId);
      }
      if (mounted) setState(() => building = false);
    }
  }

  Widget _configCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<BuildTarget>(
              initialValue: buildTarget,
              decoration: const InputDecoration(
                labelText: 'Build On',
                border: OutlineInputBorder(),
              ),
              items: BuildTarget.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: building
                  ? null
                  : (value) {
                      if (value != null) setState(() => buildTarget = value);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SyncTarget>(
              initialValue: syncTarget,
              decoration: const InputDecoration(
                labelText: 'Sync With',
                border: OutlineInputBorder(),
              ),
              items: SyncTarget.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: building
                  ? null
                  : (value) {
                      if (value != null) setState(() => syncTarget = value);
                    },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'GitHub (optional)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 8),
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
                'Use real build logs with the selected local model, edit the '
                'project, and retry within the configured safety limit.',
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
                      if (value != null) setState(() => maxCycles = value);
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
    );
  }

  Widget _phoneRunnerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Phone Runner · Termux',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: phoneRunnerBusy ? null : refreshPhoneRunner,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              phoneAvailability?.summary ??
                  'Checking Termux and Flutter ARM64…',
            ),
            const SizedBox(height: 8),
            const Text(
              'Builds stay on this phone. Nexus transfers a temporary project '
              'copy to Termux over 127.0.0.1 and receives the APK and logs '
              'back without GitHub or shared storage.',
            ),
            if (phoneRunnerStatus.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(phoneRunnerStatus),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      phoneRunnerBusy ? null : requestPhoneRunnerPermission,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Grant Permission'),
                ),
                OutlinedButton.icon(
                  onPressed: phoneRunnerBusy ? null : showExternalAppsSetup,
                  icon: const Icon(Icons.terminal),
                  label: const Text('Termux Setup'),
                ),
                FilledButton.tonalIcon(
                  onPressed: phoneRunnerBusy ? null : installPhoneRunner,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install Flutter ARM64'),
                ),
                OutlinedButton.icon(
                  onPressed: phoneRunnerBusy ? null : verifyPhoneRunner,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Verify'),
                ),
              ],
            ),
            if (phoneRunnerBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (runs.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.history),
          title: Text('No builds yet'),
          subtitle: Text(
            'Successful or failed real build attempts will appear here.',
          ),
        ),
      );
    }

    return Column(
      children: runs
          .map(
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
                  run.provider == 'phone_termux'
                      ? 'Phone · Termux'
                      : run.remoteRunId.isEmpty
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
          )
          .toList(),
    );
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
          'Nexus is local-first. Build location and synchronization are '
          'independent, so GitHub can remain completely optional.',
        ),
        const SizedBox(height: 16),
        _configCard(),
        const SizedBox(height: 12),
        _phoneRunnerCard(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Resolved build route'),
            subtitle: Text(routeSummary),
            trailing: IconButton(
              onPressed: refreshRoute,
              icon: const Icon(Icons.refresh),
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
          label: Text(building ? 'Building…' : 'Build Now'),
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
        _buildHistory(),
      ],
    );
  }
}
