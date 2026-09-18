class NexusProject {
  const NexusProject({
    required this.id,
    required this.name,
    required this.description,
    required this.framework,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String framework;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'framework': framework,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory NexusProject.fromMap(Map<String, Object?> map) {
    return NexusProject(
      id: map['id']! as String,
      name: map['name']! as String,
      description: (map['description'] as String?) ?? '',
      framework: (map['framework'] as String?) ?? 'Other',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at']! as int,
      ),
    );
  }
}
