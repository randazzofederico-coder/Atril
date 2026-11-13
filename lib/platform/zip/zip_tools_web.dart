import 'dart:convert';
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
  final src = await _ZipSource.open(zipPath);
  if (src == null) return null;
  final entries = await src.entries();
  return entries == null ? null : [for (final e in entries) e.name];
}

Future<void> unzipToDir(
  String zipPath,
  String destDir, {
  void Function(double progress)? onProgress,
}) async {
  final sw = Stopwatch()..start();
  final src = await _ZipSource.open(zipPath);
  if (src == null) throw Exception('No se encontró el archivo.');
  // Se lee el índice (al final del ZIP) y después cada entrada por separado:
  // nunca está el ZIP entero en memoria (backups de cientos de MB).
  final entries = await src.entries();
  if (entries == null) throw Exception('El archivo no es un ZIP válido.');
  final root = p.normalize(destDir);
  diag('unzip: ${entries.length} entradas desde $zipPath (${(src.size / 1048576).toStringAsFixed(1)} MB)');
  var count = 0;
  for (final e in entries) {
    if (!e.name.endsWith('/')) {
      // Protección zip-slip: ninguna entrada puede escribir fuera del destino.
      final destPath = p.normalize(p.join(root, e.name));
      if (p.isWithin(root, destPath)) {
        final bytes = await src.read(e);
        await fs.writeBytes(destPath, bytes);
        diag('unzip: ${e.name} (${(bytes.length / 1048576).toStringAsFixed(1)} MB) en ${sw.elapsedMilliseconds} ms');
      }
    }
    count++;
    onProgress?.call(entries.isEmpty ? 1.0 : count / entries.length);
    await Future<void>.delayed(Duration.zero);
  }
  diag('unzip: listo en ${sw.elapsedMilliseconds} ms');
}

class _ZipEntry {
  final String name;
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  _ZipEntry(this.name, this.method, this.compressedSize, this.uncompressedSize, this.localHeaderOffset);
}

/// ZIP leído por partes: desde un archivo del navegador ([webBlobs]) con
/// `slice`, o desde AtrilFs (en memoria; archivos chicos).
class _ZipSource {
  final web.Blob? _blob;
  final Uint8List? _bytes;
  final int size;
  _ZipSource._(this._blob, this._bytes, this.size);

  static Future<_ZipSource?> open(String path) async {
    final blob = webBlobs[path];
    if (blob != null) return _ZipSource._(blob, null, blob.size);
    if (!await fs.fileExists(path)) return null;
    final bytes = await fs.readBytes(path);
    return _ZipSource._(null, bytes, bytes.length);
  }

  Future<Uint8List> _range(int start, int end) async {
    end = end.clamp(0, size);
    start = start.clamp(0, end);
    final b = _bytes;
    if (b != null) return Uint8List.sublistView(b, start, end);
    final buffer = await _blob!.slice(start, end).arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  /// Entradas del directorio central, o null si no es un ZIP.
  Future<List<_ZipEntry>?> entries() async {
    if (size < 22) return null;
    final head = await _range(0, 4);
    if (head[0] != 0x50 || head[1] != 0x4B) return null;

    // Fin del directorio central (EOCD): en los últimos 64 KB + 22 bytes.
    final tailStart = size - 65557 < 0 ? 0 : size - 65557;
    final tail = await _range(tailStart, size);
    final td = ByteData.sublistView(tail);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (td.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;
    var count = td.getUint16(eocd + 10, Endian.little);
    var cdSize = td.getUint32(eocd + 12, Endian.little);
    var cdOffset = td.getUint32(eocd + 16, Endian.little);

    // ZIP64 (más de 4 GB o 65535 entradas)
    if ((cdOffset == 0xffffffff || cdSize == 0xffffffff || count == 0xffff) && eocd >= 20) {
      if (td.getUint32(eocd - 20, Endian.little) == 0x07064b50) {
        final recOffset = td.getUint64(eocd - 20 + 8, Endian.little);
        final rec = ByteData.sublistView(await _range(recOffset, recOffset + 56));
        if (rec.getUint32(0, Endian.little) == 0x06064b50) {
          count = rec.getUint64(32, Endian.little);
          cdSize = rec.getUint64(40, Endian.little);
          cdOffset = rec.getUint64(48, Endian.little);
        }
      }
    }

    final cd = await _range(cdOffset, cdOffset + cdSize);
    final d = ByteData.sublistView(cd);
    final out = <_ZipEntry>[];
    var pos = 0;
    for (var i = 0; i < count && pos + 46 <= cd.length; i++) {
      if (d.getUint32(pos, Endian.little) != 0x02014b50) break;
      final flags = d.getUint16(pos + 8, Endian.little);
      final method = d.getUint16(pos + 10, Endian.little);
      var comp = d.getUint32(pos + 20, Endian.little);
      var uncomp = d.getUint32(pos + 24, Endian.little);
      final nameLen = d.getUint16(pos + 28, Endian.little);
      final extraLen = d.getUint16(pos + 30, Endian.little);
      final commentLen = d.getUint16(pos + 32, Endian.little);
      var offset = d.getUint32(pos + 42, Endian.little);
      final nameBytes = Uint8List.sublistView(cd, pos + 46, pos + 46 + nameLen);
      final name = (flags & 0x800) != 0
          ? utf8.decode(nameBytes, allowMalformed: true)
          : latin1.decode(nameBytes);

      // Campo extra ZIP64: valores de 8 bytes para los que valen 0xFFFFFFFF.
      var e = pos + 46 + nameLen;
      final extraEnd = e + extraLen;
      while (e + 4 <= extraEnd) {
        final id = d.getUint16(e, Endian.little);
        final len = d.getUint16(e + 2, Endian.little);
        if (id == 0x0001) {
          var q = e + 4;
          if (uncomp == 0xffffffff) {
            uncomp = d.getUint64(q, Endian.little);
            q += 8;
          }
          if (comp == 0xffffffff) {
            comp = d.getUint64(q, Endian.little);
            q += 8;
          }
          if (offset == 0xffffffff) offset = d.getUint64(q, Endian.little);
        }
        e += 4 + len;
      }

      out.add(_ZipEntry(name, method, comp, uncomp, offset));
      pos += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  /// Contenido de una entrada (descomprimido con el Inflate de Dart puro:
  /// en WebAssembly no hay zlib nativo).
  Future<List<int>> read(_ZipEntry e) async {
    final lh = ByteData.sublistView(await _range(e.localHeaderOffset, e.localHeaderOffset + 30));
    if (lh.getUint32(0, Endian.little) != 0x04034b50) {
      throw Exception('ZIP dañado (${e.name}).');
    }
    final start = e.localHeaderOffset + 30 + lh.getUint16(26, Endian.little) + lh.getUint16(28, Endian.little);
    final data = await _range(start, start + e.compressedSize);
    switch (e.method) {
      case 0:
        return data;
      case 8:
        return Inflate.buffer(InputStream(data), e.uncompressedSize).getBytes();
      default:
        throw Exception('Compresión no soportada en ${e.name} (método ${e.method}).');
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
