import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProjectWorkspaceService {
  ProjectWorkspaceService._();

  static final ProjectWorkspaceService instance = ProjectWorkspaceService._();

  static const int _maxReadBytes = 256 * 1024;
  static const int _maxSnapshotBytes = 25 * 1024 * 1024;

  Future<Directory> projectRoot(String projectId) async {
    final support = await getApplicationSupportDirectory();
    final safeId = projectId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final root = Directory(p.join(support.path, 'projects', safeId));
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> workspaceDirectory(String projectId) async {
    final root = await projectRoot(projectId);
    final workspace = Directory(p.join(root.path, 'workspace'));
    await workspace.create(recursive: true);
    return workspace;
  }

  Future<Directory> snapshotsDirectory(String projectId) async {
    final root = await projectRoot(projectId);
    final snapshots = Directory(p.join(root.path, 'snapshots'));
    await snapshots.create(recursive: true);
    return snapshots;
  }

  Future<String> _resolve(String projectId, String relativePath) async {
    final workspace = await workspaceDirectory(projectId);
    final raw = relativePath.trim().replaceAll('\\', '/');
    final normalized = p.normalize(raw.isEmpty ? '.' : raw);

    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw StateError('Path escapes the Nexus project workspace.');
    }

    final candidate = p.normalize(p.join(workspace.path, normalized));
    if (candidate != workspace.path && !p.isWithin(workspace.path, candidate)) {
      throw StateError('Path escapes the Nexus project workspace.');
    }

    await _assertNoSymlinkTraversal(workspace.path, candidate);
    return candidate;
  }

  Future<void> _assertNoSymlinkTraversal(
    String workspacePath,
    String candidate,
  ) async {
    if (candidate == workspacePath) return;

    final relative = p.relative(candidate, from: workspacePath);
    var current = workspacePath;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      final type = await FileSystemEntity.type(
        current,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw StateError('Symbolic links are not allowed in Nexus workspaces.');
      }
      if (type == FileSystemEntityType.notFound) {
        break;
      }
    }
  }

  bool _skipDirectoryName(String name) {
    return const {
      '.git',
      '.dart_tool',
      'build',
      '.gradle',
      'node_modules',
      '.idea',
    }.contains(name);
  }

  Future<List<String>> listFiles(
    String projectId, {
    String path = '.',
    int limit = 300,
  }) async {
    final targetPath = await _resolve(projectId, path);
    final target = Directory(targetPath);
    if (!await target.exists()) {
      final file = File(targetPath);
      if (await file.exists()) {
        final workspace = await workspaceDirectory(projectId);
        return [p.relative(file.path, from: workspace.path)];
      }
      throw StateError('Path does not exist: $path');
    }

    final workspace = await workspaceDirectory(projectId);
    final result = <String>[];
    final pending = <Directory>[target];

    while (pending.isNotEmpty && result.length < limit) {
      final directory = pending.removeLast();
      await for (final entity in directory.list(followLinks: false)) {
        if (result.length >= limit) break;
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (!_skipDirectoryName(name)) pending.add(entity);
          continue;
        }
        if (entity is File) {
          result.add(p.relative(entity.path, from: workspace.path));
        }
      }
    }

    result.sort();
    return result;
  }

  Future<String> readFile(String projectId, String path) async {
    final resolved = await _resolve(projectId, path);
    final file = File(resolved);
    if (!await file.exists()) {
      throw StateError('File does not exist: $path');
    }

    final length = await file.length();
    if (length > _maxReadBytes) {
      throw StateError(
        'File is too large to read in one tool call '
        '($length bytes; limit $_maxReadBytes).',
      );
    }

    return file.readAsString();
  }

  Future<void> createFile(
    String projectId,
    String path,
    String content,
  ) async {
    final resolved = await _resolve(projectId, path);
    final file = File(resolved);
    if (await file.exists()) {
      throw StateError('File already exists: $path');
    }
    await file.parent.create(recursive: true);
    await _assertNoSymlinkTraversal(
      (await workspaceDirectory(projectId)).path,
      file.parent.path,
    );
    await file.writeAsString(content);
  }

  Future<void> writeFile(
    String projectId,
    String path,
    String content,
  ) async {
    final resolved = await _resolve(projectId, path);
    final file = File(resolved);
    await file.parent.create(recursive: true);
    await _assertNoSymlinkTraversal(
      (await workspaceDirectory(projectId)).path,
      file.parent.path,
    );
    await file.writeAsString(content);
  }

  Future<int> replaceText(
    String projectId,
    String path, {
    required String oldText,
    required String newText,
    bool all = false,
  }) async {
    if (oldText.isEmpty) {
      throw ArgumentError('old_text cannot be empty.');
    }

    final original = await readFile(projectId, path);
    final matches = RegExp(RegExp.escape(oldText)).allMatches(original).length;
    if (matches == 0) {
      throw StateError('Exact text was not found in $path.');
    }

    final updated =
        all ? original.replaceAll(oldText, newText) : original.replaceFirst(oldText, newText);
    await writeFile(projectId, path, updated);
    return all ? matches : 1;
  }

  Future<void> deleteFile(String projectId, String path) async {
    final resolved = await _resolve(projectId, path);
    final file = File(resolved);
    if (!await file.exists()) {
      throw StateError('File does not exist: $path');
    }
    await file.delete();
  }

  Future<List<Map<String, Object>>> searchCode(
    String projectId,
    String query, {
    int limit = 40,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Search query cannot be empty.');
    }

    final files = await listFiles(projectId, limit: 500);
    final results = <Map<String, Object>>[];

    for (final relativePath in files) {
      if (results.length >= limit) break;
      try {
        final text = await readFile(projectId, relativePath);
        final lines = const LineSplitter().convert(text);
        for (var index = 0; index < lines.length; index++) {
          if (lines[index].toLowerCase().contains(clean.toLowerCase())) {
            results.add({
              'path': relativePath,
              'line': index + 1,
              'text': lines[index].trim(),
            });
            if (results.length >= limit) break;
          }
        }
      } catch (_) {
        // Skip binary or oversized files.
      }
    }

    return results;
  }

  Future<String> createSnapshot(String projectId) async {
    final workspace = await workspaceDirectory(projectId);
    final snapshots = await snapshotsDirectory(projectId);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final destination = Directory(p.join(snapshots.path, stamp));
    await destination.create(recursive: true);

    var copiedBytes = 0;
    final files = await listFiles(projectId, limit: 2000);
    for (final relativePath in files) {
      final source = File(p.join(workspace.path, relativePath));
      final size = await source.length();
      if (copiedBytes + size > _maxSnapshotBytes) break;

      final target = File(p.join(destination.path, relativePath));
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      copiedBytes += size;
    }

    final metadata = File(p.join(destination.path, '.nexus_snapshot.json'));
    await metadata.writeAsString(
      jsonEncode({
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'copied_bytes': copiedBytes,
      }),
    );

    return destination.path;
  }

  Future<String> summary(String projectId) async {
    final files = await listFiles(projectId);
    if (files.isEmpty) {
      return 'Workspace is empty.';
    }
    final preview = files.take(80).join('\n');
    final suffix = files.length > 80
        ? '\n… and ${files.length - 80} more files'
        : '';
    return '${files.length} files:\n$preview$suffix';
  }
}
