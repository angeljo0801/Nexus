import 'package:flutter/material.dart';

import '../../core/models/nexus_project.dart';
import '../chat/chat_screen.dart';

class ProjectWorkspaceScreen extends StatelessWidget {
  const ProjectWorkspaceScreen({
    super.key,
    required this.project,
  });

  final NexusProject project;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Agent'),
              Tab(icon: Icon(Icons.task_alt), text: 'Tasks'),
              Tab(icon: Icon(Icons.psychology_outlined), text: 'Memory'),
              Tab(icon: Icon(Icons.build_outlined), text: 'Builds'),
              Tab(icon: Icon(Icons.sync_alt), text: 'Sync'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ChatScreen(
              projectId: project.id,
              projectName: project.name,
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
            const _ProjectPanel(
              icon: Icons.build_outlined,
              title: 'Build history',
              body:
                  'Analyze, test and build on GitHub Actions, the paired PC or this phone. Auto Fix can repair failures and retry.',
            ),
            const _ProjectPanel(
              icon: Icons.sync_alt,
              title: 'Synchronization',
              body:
                  'Phone ↔ PC ↔ GitHub synchronization uses Git history, detects conflicts and never blindly overwrites divergent work.',
            ),
          ],
        ),
      ),
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
