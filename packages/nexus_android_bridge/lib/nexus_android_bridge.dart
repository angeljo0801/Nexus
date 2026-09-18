import 'package:flutter/services.dart';

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
}
