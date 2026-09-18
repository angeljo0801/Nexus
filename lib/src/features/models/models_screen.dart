import 'package:flutter/material.dart';

import '../../core/models/local_model_definition.dart';
import '../../core/services/local_llama_runtime.dart';
import '../../core/services/local_model_manager.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final LocalModelManager manager = LocalModelManager.instance;

  @override
  void initState() {
    super.initState();
    manager.initialize();
  }

  Future<void> useModel(LocalModelDefinition model) async {
    await LocalLlamaRuntime.instance.unload();
    await manager.setActive(model);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${model.name} is now the phone AI model.')),
    );
  }

  Future<void> deleteModel(LocalModelDefinition model) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${model.name}?'),
            content: Text(
              'This removes the downloaded model and frees ${model.approximateSizeLabel} of storage. Projects and chats are not deleted.',
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
    await LocalLlamaRuntime.instance.unload();
    await manager.delete(model);
  }

  String statusText(ModelDownloadState state) {
    return switch (state.status) {
      ModelDownloadStatus.idle => 'Not installed',
      ModelDownloadStatus.downloading =>
        'Downloading ${(state.progress * 100).toStringAsFixed(1)}%',
      ModelDownloadStatus.paused =>
        'Paused ${(state.progress * 100).toStringAsFixed(1)}%',
      ModelDownloadStatus.verifying => 'Verifying SHA-256…',
      ModelDownloadStatus.installed => 'Installed',
      ModelDownloadStatus.failed => 'Download failed',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Local Models',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Download a Nexus-managed GGUF model for fully local phone inference, or use the PC model through Nexus Bridge.',
            ),
            const SizedBox(height: 20),
            for (final model in NexusModelCatalog.values) ...[
              _ModelCard(
                model: model,
                state: manager.stateFor(model),
                active: manager.activeModelId == model.id,
                statusText: statusText(manager.stateFor(model)),
                onDownload: () => manager.download(model),
                onPause: () => manager.pauseDownload(model),
                onUse: () => useModel(model),
                onDelete: () => deleteModel(model),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Use model from phone storage'),
                subtitle: const Text(
                  'Direct SAF linking without duplicating an external GGUF is reserved for the external-model adapter. Nexus-managed downloads already avoid a second copy.',
                ),
                trailing: const Icon(Icons.upcoming_outlined),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.computer),
                title: Text('PC Local Model'),
                subtitle: Text('Available after pairing with Nexus Bridge.'),
                trailing: Icon(Icons.link_off),
              ),
            ),
            const SizedBox(height: 20),
            FutureBuilder<int>(
              future: manager.installedBytes(),
              builder: (context, snapshot) {
                final bytes = snapshot.data ?? 0;
                final gb = bytes / (1024 * 1024 * 1024);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Storage',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nexus models: ${gb < 0.01 ? '0 B' : '${gb.toStringAsFixed(2)} GB'}',
                        ),
                        const Text('External models: 0 B linked'),
                        const Text('Embeddings: 0 B'),
                        const Text('Project cache: calculated separately'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.state,
    required this.active,
    required this.statusText,
    required this.onDownload,
    required this.onPause,
    required this.onUse,
    required this.onDelete,
  });

  final LocalModelDefinition model;
  final ModelDownloadState state;
  final bool active;
  final String statusText;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final downloading = state.status == ModelDownloadStatus.downloading;
    final installed = state.status == ModelDownloadStatus.installed;
    final resumable = state.status == ModelDownloadStatus.paused ||
        state.status == ModelDownloadStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(active ? Icons.memory : Icons.memory_outlined, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (active) const Chip(label: Text('Active')),
                    ],
                  ),
                  Text(model.approximateSizeLabel),
                  const SizedBox(height: 6),
                  Text(model.description),
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (downloading ||
                      state.status == ModelDownloadStatus.paused ||
                      state.status == ModelDownloadStatus.verifying) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: state.status == ModelDownloadStatus.verifying
                          ? null
                          : state.progress,
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!installed && !downloading)
                        FilledButton(
                          onPressed: onDownload,
                          child: Text(resumable ? 'Resume' : 'Download'),
                        ),
                      if (downloading)
                        FilledButton.tonal(
                          onPressed: onPause,
                          child: const Text('Pause'),
                        ),
                      if (installed && !active)
                        FilledButton(
                          onPressed: onUse,
                          child: const Text('Use'),
                        ),
                      if (installed)
                        TextButton(
                          onPressed: onDelete,
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
