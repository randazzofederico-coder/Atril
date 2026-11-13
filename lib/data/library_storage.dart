import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/fs/atril_fs.dart';

/// Handles internal file storage for the Library.
///
/// Core rule: PDFs live inside app-controlled storage (not external URIs).
/// DB rows store only the *relative* path, e.g. `docs/<docId>.pdf`.
///
/// Las rutas son de [AtrilFs]: reales en Android y virtuales en la PWA.
class LibraryStorage {
  LibraryStorage._();
  static final LibraryStorage instance = LibraryStorage._();

  String? _basePath;
  String? _docsPath;

  /// Directorio base de la biblioteca (`.../atril`).
  String get basePath {
    final d = _basePath;
    if (d == null) throw StateError('LibraryStorage not initialized');
    return d;
  }

  /// Initializes (and creates if needed) the internal folders.
  /// Idempotente: si ya está inicializado no vuelve a resolver rutas.
  Future<void> init() async {
    if (_basePath != null && _docsPath != null) return;
    final appDir = await fs.appDocumentsPath();
    final base = p.join(appDir, 'atril');
    final docs = p.join(base, 'docs');

    await fs.createDir(base);
    await fs.createDir(docs);

    _basePath = base;
    _docsPath = docs;
  }

  /// Inicializa con un directorio base arbitrario (tests).
  @visibleForTesting
  Future<void> initForTesting(String base) async {
    _basePath = base;
    _docsPath = p.join(base, 'docs');
    await fs.createDir(_docsPath!);
  }

  /// Ruta del directorio `docs/` (se usa en backups y limpieza).
  Future<String> getDocsPath() async {
    await init(); // Ensure initialized
    return _docsPath!;
  }

  String docRelPath(String docId) => p.join('docs', '$docId.pdf');

  String docAbsPath(String docId) {
    final docs = _docsPath;
    if (docs == null) {
      throw StateError('LibraryStorage not initialized');
    }
    return p.join(docs, '$docId.pdf');
  }

  /// Resolves a DB-stored relative path (e.g. `docs/<id>.pdf`) into an
  /// absolute path within internal storage.
  String absPathFromRelPath(String relPath) {
    return p.join(basePath, relPath);
  }

  /// Copies an existing PDF file into internal storage.
  /// Returns the *relative* path to persist in the DB.
  Future<String> importPdfFromExternalPath({
    required String sourcePath,
    required String docId,
  }) async {
    final destPath = docAbsPath(docId);

    if (!await fs.fileExists(sourcePath)) {
      throw StateError('No existe el archivo fuente: $sourcePath');
    }

    // Write to temp then rename (atomic within same directory).
    final tmpPath = '$destPath.tmp';
    await fs.deleteFile(tmpPath);

    try {
      if (!fs.isNative && p.basename(p.dirname(sourcePath)).startsWith('atril_pick_')) {
        // Web: archivo elegido ya copiado a un temporal propio. Moverlo es
        // mucho más liviano que copiarlo (no pasa los bytes por Dart).
        await fs.rename(sourcePath, tmpPath);
      } else {
        // La implementación nativa ya reintenta con streams si la copia
        // directa falla (Scoped Storage).
        await fs.copy(sourcePath, tmpPath);
      }
    } catch (e) {
      debugPrint('Error: no se pudo copiar el PDF importado: $e');
      // Limpiamos si quedó algo corrupto
      await fs.deleteFile(tmpPath);
      rethrow;
    }

    await fs.rename(tmpPath, destPath);

    return docRelPath(docId);
  }
}
