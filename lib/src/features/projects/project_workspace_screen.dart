import 'package:flutter/material.dart';

import '../../core/models/nexus_project.dart';
import '../../core/services/project_workspace_service.dart';
import '../chat/chat_screen.dart';
import 'project_builds_screen.dart';
import 'project_files_screen.dart';

class ProjectWorkspaceScreen extends StatefulWidget {
  const ProjectWorkspaceScreen({
    super.key,
    required this.project,
  });

  final NexusProject project;

  @override
  State<ProjectWorkspaceScreen> createState() => _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends State<ProjectWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Future<void> _workspaceReady;
  int _selectedIndex = 0;

  NexusProject get project => widget.project;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);

    _workspaceReady = ProjectWorkspaceService.instance.ensureStarterFiles(
      projectId: project.id,
      framework: project.framework,
      projectName: project.name,
      description: project.description,
    );
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final next = _tabController.index;
    if (next == _selectedIndex || !mounted) return;
    setState(() => _selectedIndex = next);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _workspaceReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(project.name)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(project.name)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not prepare the project workspace:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.name),
                Text(
                  project.framework,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              onTap: (index) {
                if (_selectedIndex != index) {
                  setState(() => _selectedIndex = index);
                }
              },
              tabs: const [
                Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Agent'),
                Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Files'),
                Tab(icon: Icon(Icons.task_alt), text: 'Tasks'),
                Tab(icon: Icon(Icons.psychology_outlined), text: 'Memory'),
                Tab(icon: Icon(Icons.build_outlined), text: 'Builds'),
                Tab(icon: Icon(Icons.sync_alt), text: 'Sync'),
              ],
            ),
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              ChatScreen(
                key: ValueKey('agent_${project.id}'),
                project: project,
              ),
              ProjectFilesScreen(
                key: ValueKey('files_${project.id}'),
                projectId: project.id,
              ),
              const _ProjectPanel(
                icon: Icons.task_alt,
                title: 'Project tasks',
                body:
                    'Nexus will break large requests into subtasks and track pending, active, completed and blocked work for this project.',
              ),
              const _ProjectPanel(
                icon: Icons.psychology_outlined,
                title: 'Project Memory',
                body:
                    'Architecture, decisions, protected paths, branch rules, build commands and preferences stay attached to this project.',
              ),
              ProjectBuildsScreen(
                key: ValueKey('builds_${project.id}'),
                project: project,
              ),
              const _ProjectPanel(
                icon: Icons.sync_alt,
                title: 'Synchronization',
                body:
                    'Phone ↔ PC ↔ GitHub synchronization uses Git history, detects conflicts and never blindly overwrites divergent work.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectPanel extends StatelessWidget {
  const _ProjectPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(icon, size: 42),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Text(body),
      ],
    );
  }
}
