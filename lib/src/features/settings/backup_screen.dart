import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool loading = true;
  bool working = false;
  bool autoEnabled = true;
  List<Map<String, dynamic>> backups = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final enabled = await NexusBackupService.autoEnabled();
    final list = await NexusBackupBridge.list();
    if (!mounted) return;
    setState(() {
      autoEnabled = enabled;
      backups = list;
      loading = false;
    });
  }

  Future<void> createBackup() async {
    setState(() => working = true);
    try {
      final result = await NexusBackupService.createManual();
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup created in Downloads/Nexus: ' +
                (result['name']?.toString() ?? 'backup'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> restore(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore Nexus backup?'),
            content: Text(
              'Current Nexus app data will be replaced with "' +
                  (item['name']?.toString() ?? 'backup') +
                  '". Local model files and encrypted GitHub credentials are not changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => working = true);
    try {
      await NexusBackupService.restore(item['uri']?.toString() ?? '');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Backup restored'),
          content: const Text(
            'Close and reopen Nexus to load the restored state.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                SystemNavigator.pop();
              },
              child: const Text('Close Nexus'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  String date(Map<String, dynamic> item) {
    final ms = (item['modifiedMs'] as num?)?.toInt();
    if (ms == null || ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} '
        '${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backups')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Daily automatic backup'),
                    subtitle: const Text(
                      'Saved in Downloads/Nexus so it survives uninstall/reinstall.',
                    ),
                    value: autoEnabled,
                    onChanged: working
                        ? null
                        : (value) async {
                            await NexusBackupService.setAutoEnabled(value);
                            if (mounted) setState(() => autoEnabled = value);
                          },
                  ),
                  FilledButton.icon(
                    onPressed: working ? null : createBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: Text(
                      working ? 'Working…' : 'Create backup now',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Includes Nexus database, chats, project memory, tasks, '
                    'integrations, preferences and local project files. '
                    'AI model files and encrypted GitHub credentials are excluded.',
                  ),
                  const Divider(height: 28),
                  if (backups.isEmpty)
                    const Text('No backups saved yet.'),
                  for (final item in backups)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: Text(item['name']?.toString() ?? 'Backup'),
                        subtitle: Text(date(item)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: working ? null : () => restore(item),
                      ),
                    ),
                ],
              ),
      );
}
