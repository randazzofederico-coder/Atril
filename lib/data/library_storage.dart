import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles internal file storage for the Library.
///
/// Core rule: PDFs live inside app-controlled storage (not external URIs).
/// DB rows store only the *relative* path, e.g. `docs/<docId>.pdf`.
class LibraryStorage {
  LibraryStorage._();
  static final LibraryStorage instance = LibraryStorage._();

  Directory? _baseDir;
  Directory? _docsDir;

  Directory get baseDir {
    final d = _baseDir;
    if (d == null) throw StateError('LibraryStorage not initialized');
    return d;
  }

  /// Initializes (and creates if needed) the internal folders.
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final base = Directory(p.join(appDir.path, 'atril'));
    final docs = Directory(p.join(base.path, 'docs'));

    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    if (!await docs.exists()) {
      await docs.create(recursive: true);
    }

    _baseDir = base;
    _docsDir = docs;
  }
  
  // Public getter so BackupManager can access it
  Future<Directory> getDocsDir() async {
      await init(); // Ensure initialized
      return _docsDir!;
  }

  String docRelPath(String docId) => p.join('docs', '$docId.pdf');

  String docAbsPath(String docId) {
    final docs = _docsDir;
    if (docs == null) {
      throw StateError('LibraryStorage not initialized');
    }
    return p.join(docs.path, '$docId.pdf');
  }

  /// Resolves a DB-stored relative path (e.g. `docs/<id>.pdf`) into an
  /// absolute path within internal storage.
  String absPathFromRelPath(String relPath) {
    return p.join(baseDir.path, relPath);
  }

  /// Copies an existing PDF file into internal storage.
  /// Returns the *relative* path to persist in the DB.
  Future<String> importPdfFromExternalPath({
    required String sourcePath,
    required String docId,
  }) async {
    final destPath = docAbsPath(docId);
    final src = File(sourcePath);
    
    if (!await src.exists()) {
      throw FileSystemException('No existe el archivo fuente', sourcePath);
    }

    // Write to temp then rename (atomic within same directory).
    final tmpPath = '$destPath.tmp';
    final tmp = File(tmpPath);
    if (await tmp.exists()) {
      await tmp.delete();
    }

    try {
      // Intento 1: Copia nativa (rápida)
      await src.copy(tmpPath);
    } catch (e) {
      debugPrint('Warning: File.copy failed ($e). Trying manual byte stream copy...');
      // Intento 2: Copia manual por streams (más robusta en Scoped Storage)
      try {
        final inStream = src.openRead();
        final outSink = tmp.openWrite();
        await inStream.pipe(outSink); // pipe cierra el sink automáticamente
      } catch (e2) {
         debugPrint('Error: Manual stream copy failed too: $e2');
         // Limpiamos si quedó algo corrupto
         if (await tmp.exists()) await tmp.delete();
         rethrow;
      }
    }

    await tmp.rename(destPath);

    return docRelPath(docId);
  }

  /// NUEVO: Guardar un PDF desde Bytes en memoria (Usado para importación SAF).
  Future<String> savePdfFromBytes({
    required Uint8List bytes,
    required String docId,
  }) async {
    final destPath = docAbsPath(docId);
    final file = File(destPath);
    
    // Si ya existe algo con ese ID (raro porque el ID es nuevo), limpiamos
    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(bytes, flush: true);
    return docRelPath(docId);
  }

  Future<void> deleteDocFile(String docId) async {
    final f = File(docAbsPath(docId));
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<String> duplicateDocFile({
    required String sourceDocId,
    required String newDocId,
  }) async {
    final src = File(docAbsPath(sourceDocId));
    if (!await src.exists()) {
      throw FileSystemException('No existe el archivo fuente', src.path);
    }

    final destPath = docAbsPath(newDocId);
    final tmpPath = '$destPath.tmp';
    await src.copy(tmpPath);
    await File(tmpPath).rename(destPath);
    return docRelPath(newDocId);
  }
}