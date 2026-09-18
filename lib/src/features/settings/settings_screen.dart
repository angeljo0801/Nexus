import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/github_auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  GitHubAccount? githubAccount;
  bool githubLoading = true;
  String githubStatus = '';

  @override
  void initState() {
    super.initState();
    loadGitHub();
  }

  Future<void> loadGitHub() async {
    final account = await GitHubAuthService.instance.account();
    if (!mounted) return;
    setState(() {
      githubAccount = account;
      githubLoading = false;
    });
  }

  Future<void> connectGitHub() async {
    final auth = GitHubAuthService.instance;

    if (!auth.appConfigured) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GitHub App setup required'),
          content: const Text(
            'This APK was built without the Nexus GitHub App client ID. '
            'The production build must include NEXUS_GITHUB_CLIENT_ID. '
            'Users will still authorize access from inside Nexus; no personal '
            'access token needs to be pasted into the app.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      githubLoading = true;
      githubStatus = 'Requesting GitHub authorization code…';
    });

    try {
      final login = await auth.beginDeviceLogin();
      if (!mounted) return;

      final proceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Connect GitHub'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Nexus will open GitHub. Enter this one-time code to '
                    'authorize the app:',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    login.userCode,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The code is also copied to the clipboard. GitHub controls '
                    'which repositories and permissions Nexus can access.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: login.userCode),
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open GitHub'),
                ),
              ],
            ),
          ) ??
          false;

      if (!proceed) {
        if (mounted) {
          setState(() {
            githubLoading = false;
            githubStatus = '';
          });
        }
        return;
      }

      await auth.openVerificationPage(login);
      if (!mounted) return;
      setState(() => githubStatus = 'Waiting for GitHub approval…');

      final account = await auth.completeDeviceLogin(
        login,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => githubStatus = status);
        },
      );

      if (!mounted) return;
      setState(() {
        githubAccount = account;
        githubLoading = false;
        githubStatus = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GitHub connected as ${account.login}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        githubLoading = false;
        githubStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub connection failed: $error')),
      );
    }
  }

  Future<void> disconnectGitHub() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Disconnect GitHub?'),
            content: const Text(
              'Nexus will delete its encrypted GitHub tokens from this device. '
              'Local projects and Git history are not deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await GitHubAuthService.instance.disconnect();
    if (!mounted) return;
    setState(() => githubAccount = null);
  }

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
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('GitHub account'),
                subtitle: Text(
                  githubLoading
                      ? (githubStatus.isEmpty
                          ? 'Checking connection…'
                          : githubStatus)
                      : githubAccount == null
                          ? 'Not connected'
                          : '@${githubAccount!.login}',
                ),
                trailing: githubLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : githubAccount == null
                        ? FilledButton.tonal(
                            onPressed: connectGitHub,
                            child: const Text('Connect'),
                          )
                        : TextButton(
                            onPressed: disconnectGitHub,
                            child: const Text('Disconnect'),
                          ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Progressive permissions'),
                subtitle: Text(
                  'GitHub grants repository access through the Nexus GitHub '
                  'App. Builds require Contents write and Actions write. '
                  'Repository creation remains a separate advanced permission.',
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Encrypted credentials'),
                subtitle: Text(
                  'Access and refresh tokens stay in Android secure storage '
                  'and are never written to project files, Git commits or AI prompts.',
                ),
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
                  'Pair by QR/code over local network, hotspot, direct '
                  'connection or supported USB transport.',
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
