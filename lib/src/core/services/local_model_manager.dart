import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_model_definition.dart';
import 'background_work_coordinator.dart';

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
}

class ExternalModelLink {
  const ExternalModelLink({
    required this.uri,
    required this.name,
  });

  final String uri;
  final String name;
}

enum ActivePhoneModelKind {
  managed,
  external,
}

class LocalModelManager extends ChangeNotifier {
  LocalModelManager._();

  static final LocalModelManager instance = LocalModelManager._();

  static const _activeModelKey = 'active_phone_model_id';
  static const _activeKindKey = 'active_phone_model_kind';
  static const _externalUriKey = 'external_model_uri';
  static const _externalNameKey = 'external_model_name';

  final Map<String, ModelDownloadState> _states = {};
  bool _initialized = false;
  String? _activeModelId;
  ActivePhoneModelKind? _activeKind;
  ExternalModelLink? _externalModel;
  String? _pauseRequestedFor;
  final NexusBackgroundWorkCoordinator _background =
      NexusBackgroundWorkCoordinator.instance;

  String? get activeModelId => _activeModelId;
  LocalModelDefinition? get activeManagedModel =>
      NexusModelCatalog.byId(_activeModelId);
  ExternalModelLink? get externalModel => _externalModel;
  ActivePhoneModelKind? get activeKind => _activeKind;

  bool get hasActiveModel {
    if (_activeKind == ActivePhoneModelKind.external) {
      return _externalModel != null && _externalModel!.uri.isNotEmpty;
    }
    return activeManagedModel != null;
  }

  String get activeDisplayName {
    if (_activeKind == ActivePhoneModelKind.external) {
      return _externalModel?.name ?? 'External GGUF';
    }
    return activeManagedModel?.name ?? 'No model selected';
  }

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
    final rawKind = preferences.getString(_activeKindKey);
    _activeKind = switch (rawKind) {
      'external' => ActivePhoneModelKind.external,
      'managed' => ActivePhoneModelKind.managed,
      _ => null,
    };

    final externalUri = preferences.getString(_externalUriKey) ?? '';
    final externalName = preferences.getString(_externalNameKey) ?? '';
    if (externalUri.isNotEmpty) {
      _externalModel = ExternalModelLink(
        uri: externalUri,
        name: externalName.isEmpty ? 'External GGUF' : externalName,
      );
    }

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
              : (bytes / model.approximateBytes)
                  .clamp(0.0, 0.99)
                  .toDouble(),
        );
      }
    }

    if (_activeKind == ActivePhoneModelKind.managed &&
        _activeModelId != null) {
      final active = NexusModelCatalog.byId(_activeModelId);
      if (active == null || !(await (await fileFor(active)).exists())) {
        _activeModelId = null;
        _activeKind = null;
        await preferences.remove(_activeModelKey);
        await preferences.remove(_activeKindKey);
      }
    }

    if (_activeKind == ActivePhoneModelKind.external &&
        _externalModel == null) {
      _activeKind = null;
      await preferences.remove(_activeKindKey);
    }

    if (_activeKind == null) {
      for (final model in NexusModelCatalog.values) {
        if (await (await fileFor(model)).exists()) {
          _activeModelId = model.id;
          _activeKind = ActivePhoneModelKind.managed;
          await preferences.setString(_activeModelKey, model.id);
          await preferences.setString(_activeKindKey, 'managed');
          break;
        }
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
    await preferences.setString(_activeKindKey, 'managed');
    _activeModelId = model.id;
    _activeKind = ActivePhoneModelKind.managed;
    notifyListeners();
  }

  Future<void> linkExternalModel({
    required String uri,
    required String name,
  }) async {
    await initialize();
    final cleanUri = uri.trim();
    if (cleanUri.isEmpty) {
      throw ArgumentError('External model URI is empty.');
    }

    final preferences = await SharedPreferences.getInstance();
    final link = ExternalModelLink(
      uri: cleanUri,
      name: name.trim().isEmpty ? 'External GGUF' : name.trim(),
    );

    await preferences.setString(_externalUriKey, link.uri);
    await preferences.setString(_externalNameKey, link.name);
    await preferences.setString(_activeKindKey, 'external');

    _externalModel = link;
    _activeKind = ActivePhoneModelKind.external;
    notifyListeners();
  }

  Future<void> useExternalModel() async {
    await initialize();
    if (_externalModel == null) {
      throw StateError('No external model is linked.');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_activeKindKey, 'external');
    _activeKind = ActivePhoneModelKind.external;
    notifyListeners();
  }

  Future<void> unlinkExternalModel() async {
    await initialize();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_externalUriKey);
    await preferences.remove(_externalNameKey);

    if (_activeKind == ActivePhoneModelKind.external) {
      await preferences.remove(_activeKindKey);
      _activeKind = null;
    }

    _externalModel = null;
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
    String? backgroundTaskId;
    var lastNotifiedPercent = -1;

    try {
      final activeTaskId = await _background.begin(
        title: 'Downloading ${model.name}',
        status:
            'Preparing download · ${(stateFor(model).progress * 100).toStringAsFixed(1)}%',
      );
      backgroundTaskId = activeTaskId;
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
            progress: total <= 0
                ? 0
                : (received / total).clamp(0.0, 0.99).toDouble(),
          );
          notifyListeners();
          return;
        }

        sink!.add(chunk);
        received += chunk.length;
        final progress = total <= 0
            ? 0.0
            : (received / total).clamp(0.0, 0.99).toDouble();
        _states[model.id] = ModelDownloadState(
          status: ModelDownloadStatus.downloading,
          progress: progress,
        );
        notifyListeners();

        final percent = (progress * 100).floor();
        if (percent >= lastNotifiedPercent + 1 || percent == 99) {
          lastNotifiedPercent = percent;
          unawaited(
            _background.update(
              activeTaskId,
              status:
                  'Downloading · ${(progress * 100).toStringAsFixed(1)}%',
            ),
          );
        }
      }

      await sink!.flush();
      await sink.close();
      sink = null;

      _states[model.id] = const ModelDownloadState(
        status: ModelDownloadStatus.verifying,
        progress: 1,
      );
      notifyListeners();
      await _background.update(
        activeTaskId,
        status: 'Download complete · verifying SHA-256…',
      );

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

      if (_activeKind == null) {
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
              : (bytes / model.approximateBytes)
                  .clamp(0.0, 0.99)
                  .toDouble(),
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
      if (backgroundTaskId != null) {
        await _background.end(backgroundTaskId);
      }
    }
  }

  Future<void> delete(LocalModelDefinition model) async {
    await initialize();
    final file = await fileFor(model);
    final partial = await _partialFileFor(model);

    if (await file.exists()) await file.delete();
    if (await partial.exists()) await partial.delete();

    if (_activeKind == ActivePhoneModelKind.managed &&
        _activeModelId == model.id) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_activeModelKey);
      await preferences.remove(_activeKindKey);
      _activeModelId = null;
      _activeKind = null;
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
