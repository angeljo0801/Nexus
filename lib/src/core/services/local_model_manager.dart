import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_model_definition.dart';

enum ModelDownloadStatus {
  idle,
  downloading,
  paused,
  verifying,
  installed,
  failed,
}

class ModelDownloadState {
  const ModelDownloadState({
    required this.status,
    this.progress = 0,
    this.error,
  });

  final ModelDownloadStatus status;
  final double progress;
  final String? error;

  ModelDownloadState copyWith({
    ModelDownloadStatus? status,
    double? progress,
    String? error,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}

class LocalModelManager extends ChangeNotifier {
  LocalModelManager._();

  static final LocalModelManager instance = LocalModelManager._();

  static const _activeModelKey = 'active_phone_model_id';

  final Map<String, ModelDownloadState> _states = {};
  bool _initialized = false;
  String? _activeModelId;
  String? _pauseRequestedFor;

  String? get activeModelId => _activeModelId;
  LocalModelDefinition? get activeModel =>
      NexusModelCatalog.byId(_activeModelId);

  ModelDownloadState stateFor(LocalModelDefinition model) {
    return _states[model.id] ??
        const ModelDownloadState(status: ModelDownloadStatus.idle);
  }

  Future<Directory> _modelsDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'models'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> fileFor(LocalModelDefinition model) async {
    final directory = await _modelsDirectory();
    return File(p.join(directory.path, model.fileName));
  }

  Future<File> _partialFileFor(LocalModelDefinition model) async {
    final directory = await _modelsDirectory();
    return File(p.join(directory.path, '${model.fileName}.part'));
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    _activeModelId = preferences.getString(_activeModelKey);

    for (final model in NexusModelCatalog.values) {
      final file = await fileFor(model);
      if (await file.exists()) {
        _states[model.id] = const ModelDownloadState(
          status: ModelDownloadStatus.installed,
          progress: 1,
        );
      } else {
        final partial = await _partialFileFor(model);
        final bytes = await partial.exists() ? await partial.length() : 0;
        _states[model.id] = ModelDownloadState(
          status: bytes > 0
              ? ModelDownloadStatus.paused
              : ModelDownloadStatus.idle,
          progress: model.approximateBytes == 0
              ? 0
              : (bytes / model.approximateBytes).clamp(0.0, 0.99).toDouble(),
        );
      }
    }

    if (_activeModelId != null) {
      final active = NexusModelCatalog.byId(_activeModelId);
      if (active == null || !(await (await fileFor(active)).exists())) {
        _activeModelId = null;
        await preferences.remove(_activeModelKey);
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<bool> isInstalled(LocalModelDefinition model) async {
    await initialize();
    return (await fileFor(model)).exists();
  }

  Future<void> setActive(LocalModelDefinition model) async {
    await initialize();
    if (!(await isInstalled(model))) {
      throw StateError('Model is not installed.');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_activeModelKey, model.id);
    _activeModelId = model.id;
    notifyListeners();
  }

  Future<void> pauseDownload(LocalModelDefinition model) async {
    _pauseRequestedFor = model.id;
  }

  Future<void> download(LocalModelDefinition model) async {
    await initialize();
    if (stateFor(model).status == ModelDownloadStatus.downloading) return;

    _pauseRequestedFor = null;
    _states[model.id] = ModelDownloadState(
      status: ModelDownloadStatus.downloading,
      progress: stateFor(model).progress,
    );
    notifyListeners();

    final partial = await _partialFileFor(model);
    var existing = await partial.exists() ? await partial.length() : 0;

    final client = HttpClient();
    IOSink? sink;

    try {
      final request = await client.getUrl(Uri.parse(model.downloadUrl));
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}.',
          uri: Uri.parse(model.downloadUrl),
        );
      }

      if (existing > 0 && response.statusCode == HttpStatus.ok) {
        existing = 0;
        if (await partial.exists()) {
          await partial.delete();
        }
      }

      sink = partial.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );

      final contentLength = response.contentLength > 0
          ? response.contentLength
          : model.approximateBytes - existing;
      final total = existing + contentLength;
      var received = existing;

      await for (final chunk in response) {
        if (_pauseRequestedFor == model.id) {
          await sink!.flush();
          await sink.close();
          sink = null;
          _states[model.id] = ModelDownloadState(
            status: ModelDownloadStatus.paused,
            progress: total <= 0 ? 0 : (received / total).clamp(0.0, 0.99).toDouble(),
          );
          notifyListeners();
          return;
        }

        sink!.add(chunk);
        received += chunk.length;
        _states[model.id] = ModelDownloadState(
          status: ModelDownloadStatus.downloading,
          progress: total <= 0 ? 0 : (received / total).clamp(0.0, 0.99).toDouble(),
        );
        notifyListeners();
      }

      await sink!.flush();
      await sink.close();
      sink = null;

      _states[model.id] = const ModelDownloadState(
        status: ModelDownloadStatus.verifying,
        progress: 1,
      );
      notifyListeners();

      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString().toLowerCase() != model.sha256.toLowerCase()) {
        throw const FormatException('Model checksum verification failed.');
      }

      final finalFile = await fileFor(model);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partial.rename(finalFile.path);

      _states[model.id] = const ModelDownloadState(
        status: ModelDownloadStatus.installed,
        progress: 1,
      );

      if (_activeModelId == null) {
        await setActive(model);
      } else {
        notifyListeners();
      }
    } catch (error) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}

      if (_pauseRequestedFor == model.id) {
        final bytes = await partial.exists() ? await partial.length() : 0;
        _states[model.id] = ModelDownloadState(
          status: ModelDownloadStatus.paused,
          progress: model.approximateBytes == 0
              ? 0
              : (bytes / model.approximateBytes).clamp(0.0, 0.99).toDouble(),
        );
      } else {
        _states[model.id] = ModelDownloadState(
          status: ModelDownloadStatus.failed,
          progress: stateFor(model).progress,
          error: error.toString(),
        );
      }
      notifyListeners();
    } finally {
      client.close(force: true);
      if (_pauseRequestedFor == model.id) {
        _pauseRequestedFor = null;
      }
    }
  }

  Future<void> delete(LocalModelDefinition model) async {
    await initialize();
    final file = await fileFor(model);
    final partial = await _partialFileFor(model);

    if (await file.exists()) await file.delete();
    if (await partial.exists()) await partial.delete();

    if (_activeModelId == model.id) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_activeModelKey);
      _activeModelId = null;
    }

    _states[model.id] =
        const ModelDownloadState(status: ModelDownloadStatus.idle);
    notifyListeners();
  }

  Future<int> installedBytes() async {
    await initialize();
    var total = 0;
    for (final model in NexusModelCatalog.values) {
      final file = await fileFor(model);
      if (await file.exists()) total += await file.length();
    }
    return total;
  }
}
