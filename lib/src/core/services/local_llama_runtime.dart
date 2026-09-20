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

  static const int _contextSize = 4096;
  // Character budgets are intentionally conservative because source code
  // tokenizes more densely than ordinary prose. This leaves room for the
  // model's generated tool call inside the 4096-token context.
  static const int _normalPromptCharBudget = 7200;
  static const int _recoveryPromptCharBudget = 4600;

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
          contextSize: _contextSize,
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
          contextSize: _contextSize,
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

      Future<String> runAttempt(
        List<llama.ChatMessage> attemptMessages,
      ) async {
        await _controller.clearContext();
        final buffer = StringBuffer();

        Stream<String> startStream() {
          return chosenTemplate == null || chosenTemplate.isEmpty
              ? _controller.generateChat(
                  messages: attemptMessages,
                  maxTokens: maxTokens,
                  temperature: temperature,
                  topP: 0.9,
                  topK: 40,
                  repeatPenalty: 1.08,
                )
              : _controller.generateChat(
                  messages: attemptMessages,
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
          if (!_isAlreadyGenerating(error)) rethrow;
          await _recoverStaleGeneration();
          stream = startStream();
        }

        try {
          await for (final token in stream) {
            buffer.write(token);
          }
        } catch (error) {
          if (!_isAlreadyGenerating(error)) rethrow;
          await _recoverStaleGeneration();
          buffer.clear();
          await for (final token in startStream()) {
            buffer.write(token);
          }
        }

        final result = buffer.toString().trim();
        if (result.isEmpty) {
          throw StateError('The local model returned an empty response.');
        }
        return result;
      }

      final compact = _compactMessages(
        messages,
        maxChars: _normalPromptCharBudget,
      );

      try {
        return await runAttempt(compact);
      } catch (error) {
        if (!_isPromptDecodeFailure(error)) rethrow;

        // llama.cpp rejects prompts that no longer fit the active context.
        // Retry once with a smaller context while preserving the system
        // instruction and the newest tool/user turns.
        try {
          await _controller.stop();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final recovery = _compactMessages(
          messages,
          maxChars: _recoveryPromptCharBudget,
          aggressive: true,
        );
        return runAttempt(recovery);
      }
    });
  }

  bool _isAlreadyGenerating(Object error) {
    return error.toString().toLowerCase().contains('already generating');
  }

  bool _isPromptDecodeFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed to decode prompt') ||
        text.contains('decode prompt') ||
        text.contains('prompt is too long') ||
        text.contains('context size') ||
        text.contains('context window');
  }

  Future<void> _recoverStaleGeneration() async {
    try {
      await _controller.stop();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _controller.clearContext();
  }

  List<llama.ChatMessage> _compactMessages(
    List<llama.ChatMessage> messages, {
    required int maxChars,
    bool aggressive = false,
  }) {
    if (messages.isEmpty) return messages;

    final systemMessages = messages
        .where((message) => message.role == 'system')
        .toList(growable: false);
    final nonSystem = messages
        .where((message) => message.role != 'system')
        .toList(growable: false);

    final result = <llama.ChatMessage>[];
    var used = 0;

    // Keep the system contract, but cap it in the emergency retry so there is
    // always space for the user's current request and the latest tool result.
    for (final message in systemMessages) {
      final content = _boundedContent(
        message.content,
        aggressive ? 2400 : 3600,
      );
      result.add(llama.ChatMessage(role: 'system', content: content));
      used += content.length;
    }

    final remaining = <llama.ChatMessage>[];
    for (final message in nonSystem.reversed) {
      final perMessageCap = aggressive ? 1600 : 3000;
      final content = _boundedContent(message.content, perMessageCap);
      final projected = used + content.length;

      if (remaining.isNotEmpty && projected > maxChars) {
        continue;
      }

      remaining.add(
        llama.ChatMessage(role: message.role, content: content),
      );
      used = projected;

      if (used >= maxChars) break;
    }

    result.addAll(remaining.reversed);

    // Ensure the compacted conversation never ends with an orphan assistant
    // turn when an older user/tool result had to be discarded.
    if (result.length > 1 &&
        result.last.role == 'assistant' &&
        nonSystem.isNotEmpty &&
        nonSystem.last.role == 'user') {
      final latest = nonSystem.last;
      result.add(
        llama.ChatMessage(
          role: 'user',
          content: _boundedContent(
            latest.content,
            aggressive ? 1200 : 2200,
          ),
        ),
      );
    }

    return result;
  }

  String _boundedContent(String content, int maxChars) {
    if (content.length <= maxChars) return content;
    if (maxChars < 200) return content.substring(0, maxChars);

    final head = (maxChars * 0.62).floor();
    final tail = maxChars - head - 90;
    return '${content.substring(0, head)}\n'
        '[…Nexus compacted older/oversized context…]\n'
        '${content.substring(content.length - math.max(0, tail))}';
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
