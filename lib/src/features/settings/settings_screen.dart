import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('GitHub'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.code),
                title: Text('GitHub account'),
                subtitle: Text('Not connected'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Progressive permissions'),
                subtitle: const Text(
                  'Request only the permission needed for the feature being enabled.',
                ),
                trailing: FilledButton.tonal(
                  onPressed: null,
                  child: const Text('Connect'),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.add_circle_outline),
                title: Text('Create repositories'),
                subtitle: Text(
                  'Advanced permission. Requested only when this capability is enabled.',
                ),
                trailing: Icon(Icons.lock_outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('PC connection'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.lan_outlined),
                title: Text('Nexus Bridge'),
                subtitle: Text('No computer paired'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Connect a PC'),
                subtitle: const Text(
                  'Pair by QR/code over local network, hotspot, direct connection or supported USB transport.',
                ),
                trailing: FilledButton.tonal(
                  onPressed: null,
                  child: const Text('Pair'),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.menu_book_outlined),
                title: Text('PC Setup Guide'),
                subtitle: Text(
                  'Install Nexus Bridge, local runtime/model and verify the connection.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Safety'),
        const Card(
          child: Column(
            children: [
              SwitchListTile(
                value: true,
                onChanged: null,
                title: Text('Automatic snapshots'),
                subtitle: Text('Create restore points before substantial edits.'),
              ),
              Divider(height: 1),
              SwitchListTile(
                value: true,
                onChanged: null,
                title: Text('Sandbox'),
                subtitle: Text('Restrict agent access to authorized workspaces/tools.'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.password_outlined),
                title: Text('Encrypted secrets'),
                subtitle: Text('Keep credentials out of source code and agent logs.'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
