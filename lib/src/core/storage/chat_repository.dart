import '../models/chat_message.dart';
import 'nexus_database.dart';

class ChatRepository {
  ChatRepository({NexusDatabase? database})
      : _database = database ?? NexusDatabase.instance;

  final NexusDatabase _database;

  Future<List<ChatMessage>> listMessages(String projectId) async {
    final db = await _database.database;
    final rows = await db.query(
      'chat_messages',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<ChatMessage> addMessage({
    required String projectId,
    required String role,
    required String content,
  }) async {
    final now = DateTime.now();
    final message = ChatMessage(
      id: 'message_${now.microsecondsSinceEpoch}',
      projectId: projectId,
      role: role,
      content: content,
      createdAt: now,
    );

    final db = await _database.database;
    await db.insert('chat_messages', message.toMap());
    return message;
  }

  Future<void> clearProjectChat(String projectId) async {
    final db = await _database.database;
    await db.delete(
      'chat_messages',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
  }
}
