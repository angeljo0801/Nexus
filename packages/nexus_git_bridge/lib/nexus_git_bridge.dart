import 'package:flutter/services.dart';

class NexusGitStatus {
  const NexusGitStatus({
    required this.branch,
    required this.clean,
    required this.added,
    required this.changed,
    required this.modified,
    required this.missing,
    required this.removed,
    required this.untracked,
  });

  final String branch;
  final bool clean;
  final List<String> added;
  final List<String> changed;
  final List<String> modified;
  final List<String> missing;
  final List<String> removed;
  final List<String> untracked;

  factory NexusGitStatus.fromMap(Map<Object?, Object?> map) {
    List<String> list(String key) =>
        (map[key] as List<Object?>? ?? const [])
            .map((value) => value.toString())
            .toList();

    return NexusGitStatus(
      branch: map['branch']?.toString() ?? '',
      clean: map['clean'] == true,
      added: list('added'),
      changed: list('changed'),
      modified: list('modified'),
      missing: list('missing'),
      removed: list('removed'),
      untracked: list('untracked'),
    );
  }

  int get changedFileCount =>
      <String>{
        ...added,
        ...changed,
        ...modified,
        ...missing,
        ...removed,
        ...untracked,
      }.length;
}

class NexusGitCommitResult {
  const NexusGitCommitResult({
    required this.sha,
    required this.message,
    required this.created,
  });

  final String sha;
  final String message;
  final bool created;

  factory NexusGitCommitResult.fromMap(Map<Object?, Object?> map) {
    return NexusGitCommitResult(
      sha: map['sha']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      created: map['created'] == true,
    );
  }
}

class NexusGitBridge {
  NexusGitBridge._();

  static const MethodChannel _channel = MethodChannel('com.nexus/git');

  static Future<void> init({
    required String repoPath,
    String branch = 'main',
  }) async {
    await _channel.invokeMethod<void>('init', {
      'repoPath': repoPath,
      'branch': branch,
    });
  }

  static Future<NexusGitStatus> status(String repoPath) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'status',
      {'repoPath': repoPath},
    );
    if (raw == null) {
      throw StateError('Git status returned no data.');
    }
    return NexusGitStatus.fromMap(raw);
  }

  static Future<String> diff(String repoPath) async {
    return await _channel.invokeMethod<String>(
          'diff',
          {'repoPath': repoPath},
        ) ??
        '';
  }

  static Future<NexusGitCommitResult> commitAll({
    required String repoPath,
    required String message,
    String authorName = 'Nexus',
    String authorEmail = 'nexus@local',
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'commitAll',
      {
        'repoPath': repoPath,
        'message': message,
        'authorName': authorName,
        'authorEmail': authorEmail,
      },
    );
    if (raw == null) {
      throw StateError('Git commit returned no data.');
    }
    return NexusGitCommitResult.fromMap(raw);
  }

  static Future<void> setRemote({
    required String repoPath,
    required String remoteUrl,
  }) async {
    await _channel.invokeMethod<void>('setRemote', {
      'repoPath': repoPath,
      'remoteUrl': remoteUrl,
    });
  }

  static Future<void> push({
    required String repoPath,
    required String token,
    String remote = 'origin',
    String branch = 'main',
  }) async {
    await _channel.invokeMethod<void>('push', {
      'repoPath': repoPath,
      'token': token,
      'remote': remote,
      'branch': branch,
    });
  }

  static Future<void> clone({
    required String remoteUrl,
    required String destinationPath,
    String? token,
    String branch = 'main',
  }) async {
    await _channel.invokeMethod<void>('clone', {
      'remoteUrl': remoteUrl,
      'destinationPath': destinationPath,
      'token': token,
      'branch': branch,
    });
  }
}
