enum AiRuntimeLocation {
  phone,
  pc,
}

abstract interface class AiRuntime {
  String get id;
  String get displayName;
  AiRuntimeLocation get location;

  Future<bool> isAvailable();

  Future<String> chat({
    required List<AiMessage> messages,
    String? projectId,
  });

  Future<void> cancel();
}

class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
  });

  final AiMessageRole role;
  final String content;
}

enum AiMessageRole {
  system,
  user,
  assistant,
  tool,
}
