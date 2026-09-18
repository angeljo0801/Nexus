import '../models/nexus_preferences.dart';
import '../models/project_integration.dart';

class ProjectSyncPolicy {
  const ProjectSyncPolicy._();

  static bool mayPush(ProjectIntegration integration) {
    return integration.syncTarget != SyncTarget.localOnly;
  }

  static bool isFullyLocal(ProjectIntegration integration) {
    return integration.syncTarget == SyncTarget.localOnly;
  }

  static String describe(ProjectIntegration integration) {
    return switch (integration.syncTarget) {
      SyncTarget.localOnly =>
        'Local Only: Nexus never pushes this project to GitHub.',
      SyncTarget.github =>
        'GitHub: commits may be pushed when a remote operation is requested.',
      SyncTarget.automatic =>
        'Automatic: Nexus keeps local Git as the source of truth and uses '
            'GitHub only when a selected feature requires it.',
    };
  }
}
