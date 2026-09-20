import 'package:flutter/services.dart';

class NexusTermuxStatus {
  const NexusTermuxStatus({
    required this.installed,
    required this.runCommandPermission,
    this.version,
  });

  final bool installed;
  final bool runCommandPermission;
  final String? version;

  factory NexusTermuxStatus.fromMap(Map<Object?, Object?> map) {
    return NexusTermuxStatus(
      installed: map['installed'] == true,
      runCommandPermission: map['runCommandPermission'] == true,
      version: map['version'] as String?,
    );
  }
}


class NexusTermuxCommandResult {
  const NexusTermuxCommandResult({
    required this.exitCode,
    required this.errCode,
    required this.stdout,
    required this.stderr,
    required this.errorMessage,
  });

  final int exitCode;
  final int errCode;
  final String stdout;
  final String stderr;
  final String errorMessage;

  bool get success => exitCode == 0 && (errCode == -1 || errCode == 0);

  factory NexusTermuxCommandResult.fromMap(Map<Object?, Object?> map) {
    return NexusTermuxCommandResult(
      exitCode: (map['exitCode'] as num?)?.toInt() ?? -1,
      errCode: (map['errCode'] as num?)?.toInt() ?? 0,
      stdout: map['stdout']?.toString() ?? '',
      stderr: map['stderr']?.toString() ?? '',
      errorMessage: map['errorMessage']?.toString() ?? '',
    );
  }
}

class NexusAndroidBridge {
  NexusAndroidBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.nexus/shared_model');

  static Future<String> openSharedModel(String uri) async {
    final path = await _channel.invokeMethod<String>(
      'openSharedModel',
      {'uri': uri},
    );
    if (path == null || path.isEmpty) {
      throw StateError('Android could not open the external GGUF.');
    }
    return path;
  }

  static Future<void> closeSharedModel() async {
    await _channel.invokeMethod<void>('closeSharedModel');
  }

  static Future<NexusTermuxStatus> termuxStatus() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'termuxStatus',
    );
    return NexusTermuxStatus.fromMap(raw ?? const {});
  }

  static Future<bool> requestTermuxRunCommandPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestTermuxRunCommandPermission',
        ) ??
        false;
  }

  static Future<void> openTermux() async {
    await _channel.invokeMethod<void>('openTermux');
  }

  static Future<void> runTermuxScript(
    String script, {
    String label = 'Nexus Phone Build',
  }) async {
    await _channel.invokeMethod<void>(
      'runTermuxScript',
      {
        'script': script,
        'label': label,
      },
    );
  }

  static Future<NexusTermuxCommandResult> runTermuxScriptForResult(
    String script, {
    String label = 'Nexus Phone Runner',
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'runTermuxScriptForResult',
      {
        'script': script,
        'label': label,
      },
    );
    return NexusTermuxCommandResult.fromMap(raw ?? const {});
  }

  static Future<bool> requestTaskNotificationPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestTaskNotificationPermission',
        ) ??
        false;
  }

  static Future<void> startBackgroundTask({
    required String title,
    required String status,
    required int startedAtMillis,
  }) async {
    await _channel.invokeMethod<void>(
      'startBackgroundTask',
      {
        'title': title,
        'status': status,
        'startedAtMillis': startedAtMillis,
      },
    );
  }

  static Future<void> updateBackgroundTask({
    required String title,
    required String status,
    required int startedAtMillis,
  }) async {
    await _channel.invokeMethod<void>(
      'updateBackgroundTask',
      {
        'title': title,
        'status': status,
        'startedAtMillis': startedAtMillis,
      },
    );
  }

  static Future<void> stopBackgroundTask() async {
    await _channel.invokeMethod<void>('stopBackgroundTask');
  }
}
