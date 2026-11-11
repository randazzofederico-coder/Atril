import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'zip_tools.dart';

Future<void> zipToFile(
  String outputPath,
  List<ZipEntrySpec> entries, {
  void Function(double progress)? onProgress,
}) {
  final specs = [
    for (final e in entries) _Entry(e.zipPath, e.sourcePath, e.bytes),
  ];
  return _runWorker(_zipWorker, _ZipArgs(outputPath, specs), onProgress);
}

Future<void> unzipToDir(
  String zipPath,
  String destDir, {
  void Function(double progress)? onProgress,
}) {
  return _runWorker(_unzipWorker, _UnzipArgs(zipPath, destDir), onProgress);
}

Future<List<String>?> listEntryNames(String zipPath) async {
  final file = File(zipPath);
  if (!await file.exists()) return null;

  // Leer los primeros bytes para verificar si es un ZIP (PK header)
  final header = await file.openRead(0, 4).fold<List<int>>(
    [],
    (prev, chunk) => prev..addAll(chunk),
  );
  if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4B) return null;

  // Solo se lee el directorio central (no se descomprime nada)
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    return [for (final entry in archive) entry.name];
  } finally {
    await input.close();
  }
}

/// Lanza el worker en un Isolate y escucha su protocolo de mensajes:
/// - `double` (0.0–1.0): progreso
/// - `'DONE'`: completado con éxito
/// - `'ERROR: ...'`: fallo con descripción
/// Si el isolate muere sin avisar (onError/onExit), también lanza.
Future<void> _runWorker<T extends _Args>(
  Future<void> Function(T) worker,
  T args,
  void Function(double)? onProgress,
) async {
  final port = ReceivePort();
  args.sendPort = port.sendPort;
  try {
    await Isolate.spawn(
      worker,
      args,
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    await for (final message in port) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message == 'DONE') {
        return;
      } else if (message is String && message.startsWith('ERROR:')) {
        throw Exception(message);
      } else if (message == null) {
        throw Exception('El proceso de compresión terminó inesperadamente.');
      } else if (message is List) {
        throw Exception('Error en el proceso de compresión: ${message.first}');
      }
    }
  } finally {
    port.close();
  }
}

abstract class _Args {
  late SendPort sendPort;
}

class _Entry {
  final String zipPath;
  final String? sourcePath;
  final List<int>? bytes;
  const _Entry(this.zipPath, this.sourcePath, this.bytes);
}

class _ZipArgs extends _Args {
  final String outputPath;
  final List<_Entry> entries;
  _ZipArgs(this.outputPath, this.entries);
}

class _UnzipArgs extends _Args {
  final String zipPath;
  final String destPath;
  _UnzipArgs(this.zipPath, this.destPath);
}

Future<void> _zipWorker(_ZipArgs args) async {
  try {
    await Directory(p.dirname(args.outputPath)).create(recursive: true);
    final encoder = ZipFileEncoder();
    encoder.create(args.outputPath);

    var count = 0;
    final total = args.entries.length;
    for (final entry in args.entries) {
      final bytes = entry.bytes;
      if (bytes != null) {
        encoder.addArchiveFile(ArchiveFile(entry.zipPath, bytes.length, bytes));
      } else {
        final file = File(entry.sourcePath!);
        if (await file.exists()) {
          await encoder.addFile(file, entry.zipPath);
        }
      }
      count++;
      args.sendPort.send(total == 0 ? 1.0 : count / total);
    }

    await encoder.close();
    args.sendPort.send('DONE');
  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}

Future<void> _unzipWorker(_UnzipArgs args) async {
  try {
    // InputFileStream para evitar cargar todo el zip a memoria
    final inputStream = InputFileStream(args.zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);

    final totalFiles = archive.length;
    var count = 0;
    final root = p.normalize(p.absolute(args.destPath));

    for (final file in archive) {
      if (file.isFile) {
        // Protección zip-slip: ninguna entrada puede escribir fuera del destino.
        final destPath = p.normalize(p.join(root, file.name));
        if (p.isWithin(root, destPath)) {
          final parentDir = Directory(p.dirname(destPath));
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          final outputStream = OutputFileStream(destPath);
          file.writeContent(outputStream);
          await outputStream.close();
        }
      }
      count++;
      if (count % 5 == 0 || count == totalFiles) {
        args.sendPort.send(count / totalFiles);
      }
    }

    await inputStream.close();
    args.sendPort.send('DONE');
  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}
