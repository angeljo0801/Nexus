import '../models/nexus_project.dart';
import '../services/project_workspace_service.dart';
import 'nexus_database.dart';

class ProjectRepository {
  ProjectRepository({NexusDatabase? database})
      : _database = database ?? NexusDatabase.instance;

  final NexusDatabase _database;

  Future<List<NexusProject>> listProjects() async {
    final db = await _database.database;
    final rows = await db.query(
      'projects',
      orderBy: 'updated_at DESC',
    );
    return rows.map(NexusProject.fromMap).toList();
  }

  Future<NexusProject> createProject({
    required String name,
    required String description,
    required String framework,
  }) async {
    final now = DateTime.now();
    final project = NexusProject(
      id: 'project_${now.microsecondsSinceEpoch}',
      name: name,
      description: description,
      framework: framework,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _database.database;
    await db.insert('projects', project.toMap());
    await ProjectWorkspaceService.instance.ensureStarterFiles(
      projectId: project.id,
      framework: project.framework,
      projectName: project.name,
      description: project.description,
    );
    return project;
  }

  Future<void> deleteProject(String projectId) async {
    final db = await _database.database;
    await db.delete(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
    );
    await ProjectWorkspaceService.instance.deleteProjectStorage(projectId);
  }
}
