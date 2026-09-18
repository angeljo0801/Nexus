import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class NexusDatabase {
  NexusDatabase._();

  static final NexusDatabase instance = NexusDatabase._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'nexus.db'),
      version: 3,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _createV1(database);
        await _createV2(database);
        await _createV3(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2(database);
        }
        if (oldVersion < 3) {
          await _createV3(database);
        }
      },
    );

    _database = db;
    return db;
  }

  Future<void> _createV1(Database database) async {
    await database.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        framework TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_chat_project_created
      ON chat_messages(project_id, created_at)
    ''');

    await database.execute('''
      CREATE TABLE project_memory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(project_id, key),
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE project_tasks (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        title TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV2(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS project_integrations (
        project_id TEXT PRIMARY KEY,
        github_repo TEXT NOT NULL DEFAULT '',
        github_branch TEXT NOT NULL DEFAULT 'main',
        github_workflow TEXT NOT NULL DEFAULT 'nexus-build.yml',
        auto_fix_enabled INTEGER NOT NULL DEFAULT 1,
        max_fix_cycles INTEGER NOT NULL DEFAULT 3,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS build_runs (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        remote_run_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        conclusion TEXT NOT NULL DEFAULT '',
        attempt INTEGER NOT NULL DEFAULT 1,
        commit_sha TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        log_excerpt TEXT NOT NULL DEFAULT '',
        started_at INTEGER NOT NULL,
        finished_at INTEGER,
        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_build_project_started
      ON build_runs(project_id, started_at DESC)
    ''');
  }

  Future<void> _createV3(Database database) async {
    await database.execute(
      "ALTER TABLE project_integrations ADD COLUMN build_target TEXT NOT NULL DEFAULT 'automatic'",
    );
    await database.execute(
      "ALTER TABLE project_integrations ADD COLUMN sync_target TEXT NOT NULL DEFAULT 'automatic'",
    );
  }
}
