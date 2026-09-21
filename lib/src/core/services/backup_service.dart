import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/nexus_database.dart';

class NexusBackupBridge {
  static const _channel = MethodChannel('com.nexus.local.nexus/backups');

  static Future<Map<String, dynamic>> write({
    required String fileName,
    required Uint8List bytes,
    bool overwrite = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writeBackup',
      {'fileName': fileName, 'bytes': bytes, 'overwrite': overwrite},
    );
    return Map<String, dynamic>.from(raw ?? const {});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listBackups');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Uint8List> read(String uri) async {
    return await _channel.invokeMethod<Uint8List>(
          'readBackup',
          {'uri': uri},
        ) ??
        Uint8List(0);
  }
}

class NexusBackupService {
  static const _enabledKey = 'nexus_auto_backup_enabled';
  static const _lastKey = 'nexus_last_auto_backup_at';

  static bool _sensitive(String key) {
    final k = key.toLowerCase();
    return k.contains('token') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('api_key') ||
        k.contains('apikey');
  }

  static bool _skipFile(File file) {
    final p = file.path.toLowerCase().replaceAll('\\', '/');
    return p.contains('/models/') ||
        p.contains('/model_cache/') ||
        p.endsWith('.gguf') ||
        p.endsWith('.safetensors');
  }

  static Future<Map<String, dynamic>> _dumpDatabase() async {
    final db = await NexusDatabase.instance.database;
    final names = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final out = <String, dynamic>{};
    for (final row in names) {
      final name = row['name']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) continue;
      final rows = await db.query(name);
      out[name] = rows;
    }
    return out;
  }

  static Future<Map<String, dynamic>> _preferences() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    final excluded = <String>[];
    for (final key in prefs.getKeys()) {
      if (_sensitive(key)) {
        excluded.add(key);
        continue;
      }
      final value = prefs.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        out[key] = value;
      }
    }
    return {'values': out, 'excluded': excluded};
  }

  static Future<void> _addDir(
    Archive archive,
    Directory root,
    String prefix,
  ) async {
    if (!await root.exists()) return;
    final base = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : root.path + Platform.pathSeparator;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || _skipFile(entity)) continue;
      if (!entity.path.startsWith(base)) continue;
      final rel = entity.path.substring(base.length).replaceAll('\\', '/');
      if (rel.isEmpty) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile('$prefix/$rel', bytes.length, bytes));
    }
  }

  static Future<Uint8List> buildBackup() async {
    final archive = Archive();
    final dbData = await _dumpDatabase();
    final prefs = await _preferences();

    final metaBytes = utf8.encode(jsonEncode({
      'format': 'NexusBackup',
      'formatVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'modelsIncluded': false,
      'encryptedCredentialsIncluded': false,
      'excludedPreferences': prefs['excluded'],
    }));
    archive.addFile(
      ArchiveFile('meta/backup.json', metaBytes.length, metaBytes),
    );

    final dbBytes = utf8.encode(jsonEncode(dbData));
    archive.addFile(
      ArchiveFile('meta/database.json', dbBytes.length, dbBytes),
    );

    final prefBytes = utf8.encode(jsonEncode(prefs['values']));
    archive.addFile(
      ArchiveFile('meta/preferences.json', prefBytes.length, prefBytes),
    );

    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    await _addDir(archive, docs, 'documents');
    if (support.path != docs.path) {
      await _addDir(archive, support, 'support');
    }

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  static Future<Map<String, dynamic>> createManual() async {
    final bytes = await buildBackup();
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return NexusBackupBridge.write(
      fileName:
          'Nexus-Backup-${now.year}${p(now.month)}${p(now.day)}-'
          '${p(now.hour)}${p(now.minute)}${p(now.second)}.zip',
      bytes: bytes,
    );
  }

  static Future<void> autoBackupIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? true)) return;
    final last = DateTime.tryParse(prefs.getString(_lastKey) ?? '');
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return;
    }
    final bytes = await buildBackup();
    await NexusBackupBridge.write(
      fileName: 'Nexus-AutoBackup.zip',
      bytes: bytes,
      overwrite: true,
    );
    await prefs.setString(_lastKey, now.toIso8601String());
  }

  static Future<bool> autoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setAutoEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  static Future<void> _clearNonModelFiles(Directory root) async {
    if (!await root.exists()) return;
    for (final entity in await root.list(followLinks: false).toList()) {
      final lower = entity.path.toLowerCase().replaceAll('\\', '/');
      if (lower.endsWith('/models') || lower.endsWith('/model_cache')) {
        continue;
      }
      if (entity is File) {
        if (_skipFile(entity)) continue;
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
  }

  static Future<void> restore(String uri) async {
    final bytes = await NexusBackupBridge.read(uri);
    if (bytes.isEmpty) throw Exception('Backup is empty.');
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? metaFile;
    ArchiveFile? dbFile;
    ArchiveFile? prefsFile;
    for (final file in archive.files) {
      if (file.name == 'meta/backup.json') metaFile = file;
      if (file.name == 'meta/database.json') dbFile = file;
      if (file.name == 'meta/preferences.json') prefsFile = file;
    }
    if (metaFile == null || dbFile == null || prefsFile == null) {
      throw Exception('Not a valid Nexus backup.');
    }
    final meta = jsonDecode(utf8.decode(metaFile.content as List<int>));
    if (meta is! Map || meta['format'] != 'NexusBackup') {
      throw Exception('Unsupported backup format.');
    }

    final dbData = jsonDecode(utf8.decode(dbFile.content as List<int>));
    if (dbData is! Map) throw Exception('Backup database is invalid.');

    final db = await NexusDatabase.instance.database;
    final existingRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final existing = existingRows
        .map((e) => e['name']?.toString() ?? '')
        .where((e) => RegExp(r'^[A-Za-z0-9_]+$').hasMatch(e))
        .toSet();

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final table in existing) {
          await txn.rawDelete('DELETE FROM "$table"');
        }
        for (final entry in dbData.entries) {
          final table = entry.key.toString();
          if (!existing.contains(table) ||
              !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(table) ||
              entry.value is! List) {
            continue;
          }
          final info = await txn.rawQuery('PRAGMA table_info("$table")');
          final columns =
              info.map((e) => e['name']?.toString() ?? '').toSet();
          for (final raw in entry.value as List) {
            if (raw is! Map) continue;
            final row = <String, Object?>{};
            for (final e in raw.entries) {
              if (columns.contains(e.key.toString())) {
                row[e.key.toString()] = e.value;
              }
            }
            if (row.isNotEmpty) {
              await txn.insert(
                table,
                row,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    await _clearNonModelFiles(docs);
    if (support.path != docs.path) await _clearNonModelFiles(support);

    for (final file in archive.files) {
      if (!file.isFile) continue;
      Directory? root;
      String? rel;
      if (file.name.startsWith('documents/')) {
        root = docs;
        rel = file.name.substring('documents/'.length);
      } else if (file.name.startsWith('support/')) {
        root = support;
        rel = file.name.substring('support/'.length);
      }
      if (root == null || rel == null || rel.isEmpty || rel.contains('..')) {
        continue;
      }
      final out = File(
        root.path +
            Platform.pathSeparator +
            rel.replaceAll('/', Platform.pathSeparator),
      );
      if (_skipFile(out)) continue;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(List<int>.from(file.content as List), flush: true);
    }

    final prefData =
        jsonDecode(utf8.decode(prefsFile.content as List<int>));
    if (prefData is Map) {
      final prefs = await SharedPreferences.getInstance();
      final auto = prefs.getBool(_enabledKey) ?? true;
      await prefs.clear();
      for (final e in prefData.entries) {
        final key = e.key.toString();
        if (_sensitive(key)) continue;
        final value = e.value;
        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is List) {
          await prefs.setStringList(
            key,
            value.map((x) => x.toString()).toList(),
          );
        }
      }
      if (!prefs.containsKey(_enabledKey)) {
        await prefs.setBool(_enabledKey, auto);
      }
    }
  }
}
