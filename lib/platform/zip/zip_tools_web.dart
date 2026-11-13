import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import '../diag_log.dart';
import '../fs/atril_fs.dart';
import '../web_blobs.dart';
import 'zip_tools.dart';

// Web: sin isolates ni dart:io.
// - Comprimir: el ZIP se escribe por partes directo a un Blob del navegador
//   (registrado en [webBlobs] con la ruta de salida), sin pasar por
//   IndexedDB ni tener el ZIP entero en memoria de Dart. Los PDFs van
//   "almacenados" (sin deflate): casi no se comprimen y deflate en el hilo
//   principal trababa la app.
// - Descomprimir: en memoria sobre AtrilFs.

Future<void> zipToFile(
  String outputPath,
  List<ZipEntrySpec> entries, {
  void Function(double progress)? onProgress,
}) async {
  final sw = Stopwatch()..start();
  diag('zip: inicio, ${entries.length} entradas -> $outputPath');
  final out = _BlobOutput();
  final encoder = ZipEncoder()..startEncode(out, level: Deflate.NO_COMPRESSION);
  var count = 0;
  for (final entry in entries) {
    List<int>? bytes = entry.bytes;
    if (bytes == null && await fs.fileExists(entry.sourcePath!)) {
      bytes = await fs.readBytes(entry.sourcePath!);
    }
    if (bytes != null) {
      final isPdf = entry.zipPath.toLowerCase().endsWith('.pdf');
      encoder.addFile(isPdf
          ? ArchiveFile.noCompress(entry.zipPath, bytes.length, bytes)
          : ArchiveFile(entry.zipPath, bytes.length, bytes));
      diag('zip: ${entry.zipPath} (${(bytes.length / 1048576).toStringAsFixed(1)} MB) '
          'en ${sw.elapsedMilliseconds} ms');
    }
    count++;
    onProgress?.call(entries.isEmpty ? 1.0 : count / entries.length);
    // Ceder el hilo para que se vea el avance.
    await Future<void>.delayed(Duration.zero);
  }
  encoder.endEncode();
  out.flush();
  final blob = web.Blob(out.parts.toJS, web.BlobPropertyBag(type: 'application/zip'));
  webBlobs[outputPath] = blob;
  diag('zip: listo, ${(blob.size / 1048576).toStringAsFixed(1)} MB en ${sw.elapsedMilliseconds} ms');
}

Future<List<String>?> listEntryNames(String zipPath) async {
  if (!await fs.fileExists(zipPath)) return null;
  final bytes = await fs.readBytes(zipPath);
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  final archive = ZipDecoder().decodeBytes(bytes);
  return [for (final entry in archive) entry.name];
}

Future<void> unzipToDir(
  String zipPath,
  String destDir, {
  void Function(double progress)? onProgress,
}) async {
  final archive = ZipDecoder().decodeBytes(await fs.readBytes(zipPath));
  final root = p.normalize(destDir);
  final total = archive.length;
  var count = 0;
  for (final file in archive) {
    if (file.isFile) {
      // Protección zip-slip: ninguna entrada puede escribir fuera del destino.
      final destPath = p.normalize(p.join(root, file.name));
      if (p.isWithin(root, destPath)) {
        await fs.writeBytes(destPath, file.content as List<int>);
      }
    }
    count++;
    if (count % 5 == 0 || count == total) {
      onProgress?.call(count / total);
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Salida del encoder que va pasando bloques de ~4 MB al lado JS (partes del
/// Blob) para no acumular el ZIP entero en memoria de Dart.
class _BlobOutput extends OutputStreamBase {
  static const _chunk = 4 * 1024 * 1024;
  final List<JSUint8Array> parts = [];
  final Uint8List _buf = Uint8List(_chunk);
  int _pos = 0;
  int _length = 0;

  @override
  int get length => _length;

  @override
  void flush() {
    if (_pos == 0) return;
    parts.add(Uint8List.fromList(Uint8List.sublistView(_buf, 0, _pos)).toJS);
    _pos = 0;
  }

  @override
  void writeByte(int value) {
    if (_pos == _chunk) flush();
    _buf[_pos++] = value & 0xff;
    _length++;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    len ??= bytes.length;
    if (len >= _chunk) {
      flush();
      final view = bytes is Uint8List ? Uint8List.sublistView(bytes, 0, len) : Uint8List.fromList(bytes.sublist(0, len));
      // Bloque grande (un PDF): directo como parte propia.
      parts.add(view.toJS);
      _length += len;
      return;
    }
    if (_pos + len > _chunk) flush();
    _buf.setRange(_pos, _pos + len, bytes);
    _pos += len;
    _length += len;
  }

  @override
  void writeInputStream(InputStreamBase stream) => writeBytes(stream.toUint8List());

  @override
  void writeUint16(int value) {
    writeByte(value & 0xff);
    writeByte((value >> 8) & 0xff);
  }

  @override
  void writeUint32(int value) {
    writeUint16(value & 0xffff);
    writeUint16((value >> 16) & 0xffff);
  }

  @override
  void writeUint64(int value) {
    writeUint32(value & 0xffffffff);
    writeUint32((value >> 32) & 0xffffffff);
  }
}
