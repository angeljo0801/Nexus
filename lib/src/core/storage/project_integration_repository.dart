import '../models/project_integration.dart';
import 'nexus_database.dart';

class ProjectIntegrationRepository {
  ProjectIntegrationRepository({NexusDatabase? database})
      : _database = database ?? NexusDatabase.instance;

  final NexusDatabase _database;

  Future<ProjectIntegration> get(String projectId) async {
    final db = await _database.database;
    final rows = await db.query(
      'project_integrations',
      where: 'project_id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ProjectIntegration.fromMap(rows.first);
    }

    final integration = ProjectIntegration(
      projectId: projectId,
      updatedAt: DateTime.now(),
    );
    await save(integration);
    return integration;
  }

  Future<void> save(ProjectIntegration integration) async {
    final db = await _database.database;
    await db.insert(
      'project_integrations',
      integration.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addBuildRun(ProjectBuildRun run) async {
    final db = await _database.database;
    await db.insert(
      'build_runs',
      run.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ProjectBuildRun>> listBuildRuns(
    String projectId, {
    int limit = 20,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'build_runs',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(ProjectBuildRun.fromMap).toList();
  }
}
