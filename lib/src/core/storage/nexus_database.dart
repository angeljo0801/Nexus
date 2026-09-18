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
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
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
      },
    );

    _database = db;
    return db;
  }
}
