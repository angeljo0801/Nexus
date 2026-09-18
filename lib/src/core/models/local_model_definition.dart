class LocalModelDefinition {
  const LocalModelDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.fileName,
    required this.downloadUrl,
    required this.approximateBytes,
    required this.sha256,
    required this.chatTemplate,
  });

  final String id;
  final String name;
  final String description;
  final String fileName;
  final String downloadUrl;
  final int approximateBytes;
  final String sha256;
  final String chatTemplate;

  String get approximateSizeLabel {
    final gb = approximateBytes / (1024 * 1024 * 1024);
    return '~${gb.toStringAsFixed(gb >= 2 ? 1 : 2)} GB';
  }
}

abstract final class NexusModelCatalog {
  static const lite = LocalModelDefinition(
    id: 'nexus_coding_lite',
    name: 'Nexus Coding Lite',
    description: 'Local coding/chat model optimized for lighter phone use.',
    fileName: 'Qwen2.5-Coder-1.5B-Instruct-Q8_0.gguf',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q8_0.gguf?download=true',
    approximateBytes: 1650000000,
    sha256:
        '717ed8f7110e9ffc8a0e1a607ec131aa9ee3a8d69d5a6e11b5e15ed7b0f6af4c',
    chatTemplate: 'chatml',
  );

  static const pro = LocalModelDefinition(
    id: 'nexus_coding_pro',
    name: 'Nexus Coding Pro',
    description: 'Larger local coding/chat model for more complex work.',
    fileName: 'Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf?download=true',
    approximateBytes: 4680000000,
    sha256:
        '1664fccab734674a50763490a8c6931b70e3f2f8ec10031b54806d30e5f956b6',
    chatTemplate: 'chatml',
  );

  static const values = [lite, pro];

  static LocalModelDefinition? byId(String? id) {
    for (final model in values) {
      if (model.id == id) return model;
    }
    return null;
  }
}
