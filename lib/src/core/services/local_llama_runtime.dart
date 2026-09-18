import 'dart:io';
import 'dart:math' as math;

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

import '../models/chat_message.dart';
import '../models/local_model_definition.dart';
import 'local_model_manager.dart';

class LocalLlamaRuntime {
  LocalLlamaRuntime._();

  static final LocalLlamaRuntime instance = LocalLlamaRuntime._();

  final llama.LlamaController _controller = llama.LlamaController();
  String? _loadedModelId;
  bool _loading = false;

  bool get isLoading => _loading;

  Future<LocalModelDefinition> _ensureLoaded() async {
    await LocalModelManager.instance.initialize();
    final model = LocalModelManager.instance.activeModel;
    if (model == null) {
      throw StateError(
        'No phone model is selected. Install one from Local Models first.',
      );
    }

    final file = await LocalModelManager.instance.fileFor(model);
    if (!await file.exists()) {
      throw StateError('The selected model file is missing.');
    }

    if (_loadedModelId == model.id && await _controller.isModelLoaded()) {
      return model;
    }

    _loading = true;
    try {
      if (await _controller.isModelLoaded()) {
        await _controller.dispose();
      }

      final gpu = await _controller.detectGpu();
      final threads = math.max(2, math.min(8, Platform.numberOfProcessors - 1));

      await _controller.loadModel(
        modelPath: file.path,
        threads: threads,
        contextSize: 4096,
        gpuLayers: gpu.recommendedGpuLayers,
      );
      _loadedModelId = model.id;
      return model;
    } finally {
      _loading = false;
    }
  }

  Future<String> generateReply({
    required String projectName,
    required List<ChatMessage> history,
  }) async {
    final model = await _ensureLoaded();

    await _controller.clearContext();

    final recent = history.length > 24
        ? history.sublist(history.length - 24)
        : history;

    final messages = <llama.ChatMessage>[
      llama.ChatMessage(
        role: 'system',
        content:
            'You are Nexus, a local-first coding assistant working inside the project "$projectName". '
            'Help the user design, understand, edit and debug software. Be concise but technically precise. '
            'When you do not have access to a requested project file or tool yet, say so instead of inventing its contents.',
      ),
      ...recent.map(
        (message) => llama.ChatMessage(
          role: message.role == 'assistant' ? 'assistant' : 'user',
          content: message.content,
        ),
      ),
    ];

    final buffer = StringBuffer();
    await for (final token in _controller.generateChat(
      messages: messages,
      template: model.chatTemplate,
      maxTokens: 1024,
      temperature: 0.45,
      topP: 0.9,
      topK: 40,
      repeatPenalty: 1.08,
    )) {
      buffer.write(token);
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw StateError('The local model returned an empty response.');
    }
    return result;
  }

  Future<void> stop() => _controller.stop();

  Future<void> unload() async {
    if (await _controller.isModelLoaded()) {
      await _controller.dispose();
    }
    _loadedModelId = null;
  }
}
