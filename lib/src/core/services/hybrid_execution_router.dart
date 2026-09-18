import '../models/nexus_preferences.dart';
import '../models/project_integration.dart';
import 'github_auth_service.dart';
import 'phone_build_runner.dart';

class HybridExecutionDecision {
  const HybridExecutionDecision({
    required this.requested,
    required this.resolved,
    required this.available,
    required this.local,
    required this.reason,
  });

  final BuildTarget requested;
  final BuildTarget? resolved;
  final bool available;
  final bool local;
  final String reason;

  bool get usesGitHub => resolved == BuildTarget.github;
  bool get usesPc => resolved == BuildTarget.pc;
  bool get usesPhone => resolved == BuildTarget.phone;
}

class HybridExecutionRouter {
  HybridExecutionRouter._();

  static final HybridExecutionRouter instance = HybridExecutionRouter._();

  final GitHubAuthService _github = GitHubAuthService.instance;
  final PhoneBuildRunner _phoneRunner = PhoneBuildRunner.instance;

  Future<HybridExecutionDecision> resolve({
    required ProjectIntegration integration,
  }) async {
    final requested = integration.buildTarget;

    final githubAvailable = await _githubAvailable(integration);
    final pcAvailable = await _pcBuildAvailable();
    final phoneBuildAvailable = await _phoneBuildAvailable();

    HybridExecutionDecision unavailable(
      String reason, {
      BuildTarget? resolved,
    }) {
      return HybridExecutionDecision(
        requested: requested,
        resolved: resolved,
        available: false,
        local: resolved != BuildTarget.github,
        reason: reason,
      );
    }

    switch (requested) {
      case BuildTarget.phone:
        if (phoneBuildAvailable) {
          return const HybridExecutionDecision(
            requested: BuildTarget.phone,
            resolved: BuildTarget.phone,
            available: true,
            local: true,
            reason: 'Using the phone-local build toolchain.',
          );
        }
        return unavailable(
          'The Termux phone runner is not ready yet. Open Phone Runner setup '
          'in Git & Builds, grant the Termux command permission and install '
          'or verify Flutter ARM64.',
          resolved: BuildTarget.phone,
        );

      case BuildTarget.pc:
        if (pcAvailable) {
          return const HybridExecutionDecision(
            requested: BuildTarget.pc,
            resolved: BuildTarget.pc,
            available: true,
            local: true,
            reason: 'Using the paired PC through Nexus Bridge.',
          );
        }
        return unavailable(
          'PC build is local/offline, but Nexus Bridge is not paired yet.',
          resolved: BuildTarget.pc,
        );

      case BuildTarget.github:
        if (integration.syncTarget == SyncTarget.localOnly) {
          return unavailable(
            'This project is set to Local Only, so Nexus will not push code '
            'to GitHub. Change Sync With if you want a GitHub Actions build.',
            resolved: BuildTarget.github,
          );
        }
        if (githubAvailable) {
          return const HybridExecutionDecision(
            requested: BuildTarget.github,
            resolved: BuildTarget.github,
            available: true,
            local: false,
            reason: 'Using GitHub Actions.',
          );
        }
        return unavailable(
          _githubUnavailableReason(integration),
          resolved: BuildTarget.github,
        );

      case BuildTarget.automatic:
        // Local-first: prefer offline-capable execution before cloud builds.
        if (pcAvailable) {
          return const HybridExecutionDecision(
            requested: BuildTarget.automatic,
            resolved: BuildTarget.pc,
            available: true,
            local: true,
            reason: 'Automatic selected the paired PC local build.',
          );
        }
        if (phoneBuildAvailable) {
          return const HybridExecutionDecision(
            requested: BuildTarget.automatic,
            resolved: BuildTarget.phone,
            available: true,
            local: true,
            reason: 'Automatic selected the phone-local build.',
          );
        }
        if (githubAvailable &&
            integration.syncTarget != SyncTarget.localOnly) {
          return const HybridExecutionDecision(
            requested: BuildTarget.automatic,
            resolved: BuildTarget.github,
            available: true,
            local: false,
            reason:
                'No local build runner is currently available, so Automatic '
                'selected GitHub Actions.',
          );
        }

        final localOnly = integration.syncTarget == SyncTarget.localOnly;
        return unavailable(
          localOnly
              ? 'Automatic is staying fully local. Local AI, project files '
                  'and Git continue to work, but no local build runner is '
                  'available until Nexus Bridge is paired or a supported '
                  'phone toolchain is installed.'
              : 'No build runner is available. Local AI, files and Git still '
                  'work. Connect GitHub for Actions or pair Nexus Bridge for '
                  'an offline PC build.',
        );
    }
  }

  Future<bool> _pcBuildAvailable() async {
    // Nexus Bridge will provide this dynamically when paired.
    return false;
  }

  Future<bool> _phoneBuildAvailable() async {
    try {
      return (await _phoneRunner.availability()).ready;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _githubAvailable(ProjectIntegration integration) async {
    if (!integration.githubConfigured ||
        !integration.githubSyncAllowed ||
        !_github.appConfigured) {
      return false;
    }

    try {
      final token = await _github.accessToken();
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _githubUnavailableReason(ProjectIntegration integration) {
    if (!integration.githubSyncAllowed) {
      return 'GitHub access is disabled by the Local Only sync setting.';
    }
    if (!integration.githubConfigured) {
      return 'Configure a GitHub repository, branch and workflow for this project.';
    }
    if (!_github.appConfigured) {
      return 'This APK does not yet contain the Nexus GitHub App client ID.';
    }
    return 'GitHub is not connected or its authorization has expired.';
  }
}
