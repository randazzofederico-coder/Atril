import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'atril_fs.dart';

AtrilFs createPlatformFs() => IoAtrilFs();

/// Implementación nativa (Android/escritorio/tests) sobre `dart:io`.
class IoAtrilFs extends AtrilFs {
  @override
  bool get isNative => true;

  @override
  Future<String> appDocumentsPath() async => (await getApplicationDocumentsDirectory()).path;

  @override
  Future<String> tempPath() async => (await getTemporaryDirectory()).path;

  @override
  String? get systemTempPath {
    try {
      return Directory.systemTemp.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> createTempDir(String prefix) async {
    final base = Directory(await tempPath());
    if (!await base.exists()) await base.create(recursive: true);
    return (await base.createTemp(prefix)).path;
  }

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> dirExists(String path) => Directory(path).exists();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<DateTime?> modified(String path) async {
    try {
      return (await FileStat.stat(path)).modified;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FsEntry>> list(String dir, {bool recursive = false}) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <FsEntry>[];
    await for (final e in d.list(recursive: recursive, followLinks: false)) {
      if (e is File) {
        out.add(FsEntry(e.path, isDirectory: false));
      } else if (e is Directory) {
        out.add(FsEntry(e.path, isDirectory: true));
      }
    }
    return out;
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await _ensureParent(path);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeString(String path, String contents) async {
    await _ensureParent(path);
    await File(path).writeAsString(contents, flush: true);
  }

  @override
  Future<void> createDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> copy(String from, String to) async {
    await _ensureParent(to);
    final src = File(from);
    try {
      await src.copy(to);
    } catch (_) {
      // Copia por streams: más robusta con algunos proveedores (Scoped Storage).
      final tmp = File(to);
      try {
        await src.openRead().pipe(tmp.openWrite());
      } catch (e) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        rethrow;
      }
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    await _ensureParent(to);
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteDir(String path) async {
    final d = Directory(path);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> _ensureParent(String path) async {
    final parent = Directory(p.dirname(path));
    if (!await parent.exists()) await parent.create(recursive: true);
  }
}
