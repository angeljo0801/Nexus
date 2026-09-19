import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexus_android_bridge/nexus_android_bridge.dart';

class NexusBackgroundTask {
  const NexusBackgroundTask({
    required this.id,
    required this.title,
    required this.status,
    required this.startedAt,
  });

  final String id;
  final String title;
  final String status;
  final DateTime startedAt;

  NexusBackgroundTask copyWith({
    String? status,
  }) {
    return NexusBackgroundTask(
      id: id,
      title: title,
      status: status ?? this.status,
      startedAt: startedAt,
    );
  }
}

class NexusBackgroundWorkCoordinator extends ChangeNotifier {
  NexusBackgroundWorkCoordinator._();

  static final NexusBackgroundWorkCoordinator instance =
      NexusBackgroundWorkCoordinator._();

  final Map<String, NexusBackgroundTask> _tasks =
      <String, NexusBackgroundTask>{};
  int _sequence = 0;
  bool _notificationPermissionRequested = false;

  List<NexusBackgroundTask> get activeTasks =>
      List.unmodifiable(_tasks.values);

  NexusBackgroundTask? get currentTask =>
      _tasks.isEmpty ? null : _tasks.values.last;

  bool get hasActiveTasks => _tasks.isNotEmpty;

  Future<String> begin({
    required String title,
    required String status,
  }) async {
    final id =
        'task_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    final task = NexusBackgroundTask(
      id: id,
      title: title,
      status: status,
      startedAt: DateTime.now(),
    );
    _tasks[id] = task;
    notifyListeners();

    await _ensureNotificationPermission();

    try {
      if (_tasks.length == 1) {
        await NexusAndroidBridge.startBackgroundTask(
          title: _notificationTitle(task),
          status: task.status,
          startedAtMillis: task.startedAt.millisecondsSinceEpoch,
        );
      } else {
        await _refreshNotification();
      }
    } catch (_) {}

    return id;
  }

  Future<void> update(
    String id, {
    required String status,
  }) async {
    final current = _tasks[id];
    if (current == null) return;

    _tasks[id] = current.copyWith(status: status);
    notifyListeners();

    try {
      await _refreshNotification(preferredTaskId: id);
    } catch (_) {}
  }

  Future<void> end(String id) async {
    _tasks.remove(id);
    notifyListeners();

    try {
      if (_tasks.isEmpty) {
        await NexusAndroidBridge.stopBackgroundTask();
      } else {
        await _refreshNotification();
      }
    } catch (_) {}
  }

  Future<void> _ensureNotificationPermission() async {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      await NexusAndroidBridge.requestTaskNotificationPermission();
    } catch (_) {}
  }

  Future<void> _refreshNotification({
    String? preferredTaskId,
  }) async {
    if (_tasks.isEmpty) return;

    final task = preferredTaskId == null
        ? _tasks.values.last
        : (_tasks[preferredTaskId] ?? _tasks.values.last);

    await NexusAndroidBridge.updateBackgroundTask(
      title: _notificationTitle(task),
      status: task.status,
      startedAtMillis: task.startedAt.millisecondsSinceEpoch,
    );
  }

  String _notificationTitle(NexusBackgroundTask task) {
    if (_tasks.length <= 1) return task.title;
    return '${task.title} · ${_tasks.length} tasks active';
  }

  static String formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
