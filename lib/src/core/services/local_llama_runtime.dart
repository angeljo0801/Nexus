import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;
import 'package:nexus_android_bridge/nexus_android_bridge.dart';

import '../models/chat_message.dart';
import 'local_model_manager.dart';

class _ResolvedModel {
  const _ResolvedModel({
    required this.key,
    required this.path,
    this.template,
    required this.external,
  });

  final String key;
  final String path;
  final String? template;
  final bool external;
}

class LocalLlamaRuntime {
  LocalLlamaRuntime._();

  static final LocalLlamaRuntime instance = LocalLlamaRuntime._();

  llama.LlamaController _controller = llama.LlamaController();
  String? _loadedModelKey;
  bool _loadedFromExternal = false;
  bool _loading = false;
  Completer<void>? _generationGate;

  bool get isLoading => _loading;
  bool get isGenerating => _generationGate != null;

  Future<T> _withGenerationLock<T>(Future<T> Function() action) async {
    while (_generationGate != null) {
      await _generationGate!.future;
    }

    final gate = Completer<void>();
    _generationGate = gate;
    try {
      return await action();
    } finally {
      if (identical(_generationGate, gate)) {
        _generationGate = null;
      }
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  Future<_ResolvedModel> _resolveActiveModel() async {
    final manager = LocalModelManager.instance;
    await manager.initialize();

    if (manager.activeKind == ActivePhoneModelKind.external) {
      final external = manager.externalModel;
      if (external == null || external.uri.isEmpty) {
        throw StateError('The external GGUF link is missing.');
      }
      final fdPath = await NexusAndroidBridge.openSharedModel(external.uri);
      return _ResolvedModel(
        key: 'external:${external.uri}',
        path: fdPath,
        external: true,
      );
    }

    final model = manager.activeManagedModel;
    if (model == null) {
      throw StateError(
        'No phone model is selected. Install or link one from Local Models first.',
      );
    }

    final file = await manager.fileFor(model);
    if (!await file.exists()) {
      throw StateError('The selected managed model file is missing.');
    }

    return _ResolvedModel(
      key: 'managed:${model.id}',
      path: file.path,
      template: model.chatTemplate,
      external: false,
    );
  }

  Future<_ResolvedModel> _ensureLoaded() async {
    final manager = LocalModelManager.instance;
    await manager.initialize();

    final expectedKey = manager.activeKind == ActivePhoneModelKind.external
        ? 'external:${manager.externalModel?.uri ?? ''}'
        : 'managed:${manager.activeManagedModel?.id ?? ''}';

    if (_loadedModelKey == expectedKey &&
        await _controller.isModelLoaded()) {
      final external = manager.activeKind == ActivePhoneModelKind.external;
      return _ResolvedModel(
        key: expectedKey,
        path: '',
        template: external ? null : manager.activeManagedModel?.chatTemplate,
        external: external,
      );
    }

    _loading = true;
    try {
      await unload();
      final resolved = await _resolveActiveModel();

      final threads =
          math.max(2, math.min(8, Platform.numberOfProcessors - 1));

      var gpuLayers = 0;
      try {
        final gpu = await _controller.detectGpu();
        if (gpu.vulkanSupported) {
          gpuLayers = gpu.recommendedGpuLayers;
        }
      } catch (_) {
        gpuLayers = 0;
      }

      try {
        await _controller.loadModel(
          modelPath: resolved.path,
          threads: threads,
          contextSize: 4096,
          gpuLayers: gpuLayers,
        );
      } catch (_) {
        if (gpuLayers <= 0) rethrow;
        try {
          await _controller.dispose();
        } catch (_) {}
        _controller = llama.LlamaController();
        await _controller.loadModel(
          modelPath: resolved.path,
          threads: threads,
          contextSize: 4096,
          gpuLayers: 0,
        );
      }

      _loadedModelKey = resolved.key;
      _loadedFromExternal = resolved.external;
      return resolved;
    } catch (_) {
      if (_loadedFromExternal ||
          LocalModelManager.instance.activeKind ==
              ActivePhoneModelKind.external) {
        try {
          await NexusAndroidBridge.closeSharedModel();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _loading = false;
    }
  }

  Future<String> generateReply({
    required String projectName,
    required List<ChatMessage> history,
  }) async {
    final resolved = await _ensureLoaded();

    await _controller.clearContext();

    final recent =
        history.length > 24 ? history.sublist(history.length - 24) : history;

    final messages = <llama.ChatMessage>[
      llama.ChatMessage(
        role: 'system',
        content:
            'You are Nexus, a local-first coding assistant working inside the project "$projectName". '
            'Help the user design, understand, edit and debug software. Be concise but technically precise. '
            'Never claim you changed a file unless a Nexus tool actually changed it.',
      ),
      ...recent.map(
        (message) => llama.ChatMessage(
          role: message.role == 'assistant' ? 'assistant' : 'user',
          content: message.content,
        ),
      ),
    ];

    return generateMessages(
      messages: messages,
      maxTokens: 1024,
      temperature: 0.45,
      template: resolved.template,
    );
  }

  Future<String> generateMessages({
    required List<llama.ChatMessage> messages,
    int maxTokens = 1200,
    double temperature = 0.25,
    String? template,
  }) {
    return _withGenerationLock(() async {
      final resolved = await _ensureLoaded();
      final chosenTemplate = template ?? resolved.template;

      await _controller.clearContext();
      final buffer = StringBuffer();

      Stream<String> startStream() {
        return chosenTemplate == null || chosenTemplate.isEmpty
            ? _controller.generateChat(
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: 0.9,
                topK: 40,
                repeatPenalty: 1.08,
              )
            : _controller.generateChat(
                messages: messages,
                template: chosenTemplate,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: 0.9,
                topK: 40,
                repeatPenalty: 1.08,
              );
      }

      Stream<String> stream;
      try {
        stream = startStream();
      } catch (error) {
        final message = error.toString();
        if (!message.contains('Already generating')) rethrow;

        // Recover a stale controller generation state left by an interrupted
        // stream before attempting one clean restart.
        try {
          await _controller.stop();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _controller.clearContext();
        stream = startStream();
      }

      await for (final token in stream) {
        buffer.write(token);
      }

      final result = buffer.toString().trim();
      if (result.isEmpty) {
        throw StateError('The local model returned an empty response.');
      }
      return result;
    });
  }

  Future<void> stop() => _controller.stop();

  Future<void> unload() async {
    try {
      if (await _controller.isModelLoaded()) {
        await _controller.dispose();
      }
    } catch (_) {}

    _controller = llama.LlamaController();
    _loadedModelKey = null;

    if (_loadedFromExternal) {
      try {
        await NexusAndroidBridge.closeSharedModel();
      } catch (_) {}
    }
    _loadedFromExternal = false;
  }
}
