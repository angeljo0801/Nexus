import 'package:flutter/material.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Projects',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Local Git workspaces with independent Project Memory, build rules and sync state.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.add_box_outlined, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Open or clone a project',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Clone from GitHub, open a local repository, or create a new repository after GitHub permissions are granted.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add project'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.psychology_outlined),
            title: Text('Project Memory'),
            subtitle: Text(
              'Architecture, branch rules, protected paths, build commands and decisions are stored separately from chat history.',
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.sync_alt),
            title: Text('Git-backed synchronization'),
            subtitle: Text(
              'Phone ↔ PC ↔ GitHub with conflict detection instead of blind overwrites.',
            ),
          ),
        ),
      ],
    );
  }
}
