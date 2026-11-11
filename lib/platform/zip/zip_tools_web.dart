import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../fs/atril_fs.dart';
import 'zip_tools.dart';

// Web: sin isolates ni dart:io. Todo en memoria sobre AtrilFs, cediendo el
// hilo entre archivos para que la UI muestre el progreso.

Future<void> zipToFile(
  String outputPath,
  List<ZipEntrySpec> entries, {
  void Function(double progress)? onProgress,
}) async {
  final archive = Archive();
  var count = 0;
  for (final entry in entries) {
    List<int>? bytes = entry.bytes;
    if (bytes == null && await fs.fileExists(entry.sourcePath!)) {
      bytes = await fs.readBytes(entry.sourcePath!);
    }
    if (bytes != null) {
      archive.addFile(ArchiveFile(entry.zipPath, bytes.length, bytes));
    }
    count++;
    onProgress?.call(entries.isEmpty ? 1.0 : count / entries.length);
    await Future<void>.delayed(Duration.zero);
  }
  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) throw Exception('No se pudo generar el ZIP.');
  await fs.writeBytes(outputPath, zipped);
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
