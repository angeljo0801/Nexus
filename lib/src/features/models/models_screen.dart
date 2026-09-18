import 'package:flutter/material.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          'Download Nexus-managed models, link an existing GGUF file, or use the PC model through Nexus Bridge.',
        ),
        const SizedBox(height: 20),
        const _ModelCard(
          name: 'Nexus Coding Lite',
          size: '~2 GB',
          description: 'Chat + Coding + Agent. Recommended for lighter phone use.',
        ),
        const SizedBox(height: 12),
        const _ModelCard(
          name: 'Nexus Coding Pro',
          size: '~5 GB',
          description: 'Chat + Coding + Agent. Better for complex multi-file work.',
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Use model from phone storage'),
            subtitle: const Text(
              'Link an existing compatible GGUF without duplicating the file.',
            ),
            trailing: FilledButton.tonal(
              onPressed: null,
              child: const Text('Select'),
            ),
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
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text('Nexus models: 0 B'),
                Text('External models: 0 B linked'),
                Text('Embeddings: 0 B'),
                Text('Project cache: 0 B'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.name,
    required this.size,
    required this.description,
  });

  final String name;
  final String size;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.memory, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(size),
                  const SizedBox(height: 6),
                  Text(description),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: null,
                    child: const Text('Download'),
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
