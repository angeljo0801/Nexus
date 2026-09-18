class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.projectId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String role;
  final String content;
  final DateTime createdAt;

  bool get fromUser => role == 'user';

  Map<String, Object?> toMap() => {
        'id': id,
        'project_id': projectId,
        'role': role,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromMap(Map<String, Object?> map) {
    return ChatMessage(
      id: map['id']! as String,
      projectId: map['project_id']! as String,
      role: map['role']! as String,
      content: map['content']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
      ),
    );
  }
}
