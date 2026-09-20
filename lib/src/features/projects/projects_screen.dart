import 'package:flutter/material.dart';

import '../../core/models/nexus_project.dart';
import '../../core/services/project_workspace_service.dart';
import '../../core/storage/project_repository.dart';
import 'project_workspace_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectDraft {
  const _ProjectDraft({
    required this.name,
    required this.description,
    required this.framework,
  });

  final String name;
  final String description;
  final String framework;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String _framework = 'Flutter';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final projectName = _name.text.trim();
    if (projectName.isEmpty) return;

    Navigator.of(context).pop(
      _ProjectDraft(
        name: projectName,
        description: _description.text.trim(),
        framework: _framework,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New app project'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Project name',
                hintText: 'My App',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'What do you want to build?',
                hintText: 'Describe the application and its main goal.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _framework,
              decoration: const InputDecoration(
                labelText: 'Starting framework',
              ),
              items: const [
                DropdownMenuItem(value: 'Flutter', child: Text('Flutter')),
                DropdownMenuItem(
                  value: 'Android Native',
                  child: Text('Android Native'),
                ),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value == null || value == _framework) return;
                setState(() => _framework = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create Project'),
        ),
      ],
    );
  }
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final ProjectRepository repository = ProjectRepository();
  List<NexusProject> projects = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadProjects();
  }

  Future<void> loadProjects() async {
    final result = await repository.listProjects();
    if (!mounted) return;
    setState(() {
      projects = result;
      loading = false;
    });
  }

  Future<void> createProject() async {
    final draft = await showDialog<_ProjectDraft>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );

    if (draft == null || !mounted) return;

    // Let the dialog finish its route teardown before creating/pushing the
    // project workspace. This avoids overlapping the dialog's inherited
    // widget deactivation with the next route.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final project = await repository.createProject(
      name: draft.name,
      description: draft.description,
      framework: draft.framework,
    );

    if (!mounted) return;
    await loadProjects();
    if (!mounted) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await openProject(project);
  }

  Future<void> deleteProject(NexusProject project) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete project?'),
            content: Text(
              'Delete "${project.name}" from Nexus? Its local chat, tasks and Project Memory will also be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await repository.deleteProject(project.id);
    await loadProjects();
  }

  Future<void> openProject(NexusProject project) async {
    await ProjectWorkspaceService.instance.ensureStarterFiles(
      projectId: project.id,
      framework: project.framework,
      projectName: project.name,
      description: project.description,
    );
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectWorkspaceScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Projects',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: createProject,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Every application gets its own AI conversation, Project Memory, tasks, builds, Git repository and sync state.',
        ),
        const SizedBox(height: 20),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (projects.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.rocket_launch_outlined, size: 34),
                  const SizedBox(height: 12),
                  Text(
                    'Create your first application',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start from an idea. Nexus will keep the coding conversation, decisions and development history inside this project.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: createProject,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Create App Project'),
                  ),
                ],
              ),
            ),
          )
        else
          ...projects.map(
            (project) => Card(
              child: ListTile(
                leading: const Icon(Icons.apps),
                title: Text(project.name),
                subtitle: Text(
                  project.description.isEmpty
                      ? project.framework
                      : '${project.framework} · ${project.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      deleteProject(project);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete project'),
                    ),
                  ],
                ),
                onTap: () => openProject(project),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.cloud_download_outlined),
                title: Text('Clone from GitHub'),
                subtitle: Text(
                  'Bring an existing repository into a Nexus project and attach memory, chat and build settings to it.',
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('Open local repository'),
                subtitle: Text(
                  'Use a repository already stored on the phone or paired PC.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
