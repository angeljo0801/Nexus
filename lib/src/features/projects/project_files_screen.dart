import 'package:flutter/material.dart';

import '../../core/services/project_workspace_service.dart';

class ProjectFilesScreen extends StatefulWidget {
  const ProjectFilesScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  State<ProjectFilesScreen> createState() => _ProjectFilesScreenState();
}

class _ProjectFilesScreenState extends State<ProjectFilesScreen> {
  final ProjectWorkspaceService workspace = ProjectWorkspaceService.instance;
  List<String> files = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await workspace.listFiles(widget.projectId);
      if (!mounted) return;
      setState(() {
        files = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> openFile(String path) async {
    try {
      final content = await workspace.readFile(widget.projectId, path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 800,
              maxHeight: 700,
            ),
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: files.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 100),
                Icon(Icons.folder_open, size: 42),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'This project workspace is empty.\nAsk the Agent to create the application.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final path = files[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openFile(path),
                  ),
                );
              },
            ),
    );
  }
}
