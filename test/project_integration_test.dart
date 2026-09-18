import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/src/core/models/nexus_preferences.dart';
import 'package:nexus/src/core/models/project_integration.dart';

void main() {
  test('project integration defaults to hybrid automatic routing', () {
    final integration = ProjectIntegration.fromMap({
      'project_id': 'p1',
      'github_repo': '',
      'github_branch': 'main',
      'github_workflow': 'nexus-build.yml',
      'auto_fix_enabled': 1,
      'max_fix_cycles': 3,
      'updated_at': 1,
    });

    expect(integration.buildTarget, BuildTarget.automatic);
    expect(integration.syncTarget, SyncTarget.automatic);
    expect(integration.githubSyncAllowed, isTrue);
  });

  test('local only sync persists and blocks GitHub sync', () {
    final integration = ProjectIntegration(
      projectId: 'p2',
      buildTarget: BuildTarget.automatic,
      syncTarget: SyncTarget.localOnly,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    );

    final restored = ProjectIntegration.fromMap(integration.toMap());

    expect(restored.syncTarget, SyncTarget.localOnly);
    expect(restored.buildTarget, BuildTarget.automatic);
    expect(restored.githubSyncAllowed, isFalse);
  });
}
