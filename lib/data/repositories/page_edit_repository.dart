import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_data.dart';
import '../app_database.dart';
import 'pdf_manipulator.dart';

/// Edición de páginas de un PDF **preservando las anotaciones**, con la
/// posibilidad de deshacer la última edición guardada.
///
/// Las anotaciones se guardan por número de página (`pageIndex`, 1-based).
/// Al reordenar/eliminar páginas:
/// - Las anotaciones de una página original se mueven con ella.
/// - Las anotaciones de páginas eliminadas se borran.
/// - Las páginas nuevas (fotos, galería, otro PDF) empiezan sin anotaciones.
///
/// Antes de sobrescribir el PDF se guarda una copia del PDF anterior y de sus
/// anotaciones en `atril/page_edit_undo/<docId>/` (fuera de `docs/`, para no
/// inflar los backups). Se conserva un solo nivel de deshacer por documento.
class PageEditRepository {
  PageEditRepository._();

  static const _undoDirName = 'page_edit_undo';
  static const _undoPdfName = 'doc.pdf';
  static const _undoMetaName = 'annotations.json';

  /// Se incrementa cada vez que cambian las páginas de un documento
  /// (guardar edición, deshacer o restauración por error). Los visores
  /// escuchan esto para recargar si el documento abierto es [lastEditedDocId].
  static final ValueNotifier<int> editRevision = ValueNotifier<int>(0);
  static String? lastEditedDocId;

  static void _notifyEdited(String docId) {
    lastEditedDocId = docId;
    editRevision.value++;
  }

  // ---------------------------------------------------------------------------
  // MAPEO DE PÁGINAS (puro, testeable)
  // ---------------------------------------------------------------------------

  /// Calcula página vieja (1-based) → página nueva (1-based) a partir del
  /// orden final. Las páginas originales que no aparecen fueron eliminadas.
  static Map<int, int> buildPageMapping(List<PageEditEntry> pageOrder) {
    final mapping = <int, int>{};
    for (var i = 0; i < pageOrder.length; i++) {
      final orig = pageOrder[i].originalPageIndex;
      if (orig != null) mapping.putIfAbsent(orig + 1, () => i + 1);
    }
    return mapping;
  }

  // ---------------------------------------------------------------------------
  // GUARDAR EDICIÓN
  // ---------------------------------------------------------------------------

  /// Genera el PDF editado, lo guarda en [pdfPath] y reubica las anotaciones.
  ///
  /// Si algo falla después de sobrescribir el PDF, se restaura el estado
  /// anterior (PDF + anotaciones) automáticamente.
  static Future<void> applyPageEdits({
    required String docId,
    required String pdfPath,
    required List<PageEditEntry> pageOrder,
    void Function(int current, int total)? onProgress,
  }) async {
    // 1. Generar el nuevo PDF en memoria (el original sigue intacto)
    final pdfBytes = await PdfManipulator.applyEdits(
      sourcePdfPath: pdfPath,
      pageOrder: pageOrder,
      onProgress: onProgress,
    );

    // 2. Guardar punto de restauración (PDF actual + anotaciones actuales)
    final snapshot = await _saveUndoSnapshot(docId, pdfPath);

    try {
      // 3. Escribir el PDF (atómico: temp + rename)
      await _atomicWrite(pdfPath, pdfBytes);

      // 4. Reubicar anotaciones
      await AppData.db.remapAnnotationPages(docId, buildPageMapping(pageOrder));
    } catch (e) {
      debugPrint('Error guardando edición de páginas, restaurando: $e');
      await _restoreFromSnapshot(docId, pdfPath, snapshot);
      rethrow;
    } finally {
      LibraryRepository.invalidatePageCountCache(pdfPath);
      _notifyEdited(docId);
    }
  }

  // ---------------------------------------------------------------------------
  // DESHACER
  // ---------------------------------------------------------------------------

  /// `true` si hay una edición de páginas guardada que se puede deshacer.
  static Future<bool> hasUndo(String docId) async {
    final dir = await _undoDir(docId);
    return File(p.join(dir.path, _undoPdfName)).exists();
  }

  /// Fecha de la última edición deshacible, o null.
  static Future<DateTime?> undoTimestamp(String docId) async {
    try {
      final dir = await _undoDir(docId);
      final meta = File(p.join(dir.path, _undoMetaName));
      if (!await meta.exists()) return null;
      final json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final ms = json['savedAt'] as int?;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Restaura el PDF y las anotaciones al estado previo a la última edición
  /// de páginas guardada. Luego descarta el punto de restauración.
  static Future<void> undoLastEdit({required String docId, required String pdfPath}) async {
    final dir = await _undoDir(docId);
    final snapshot = _UndoSnapshot(dir);
    if (!await File(snapshot.pdfPath).exists()) {
      throw Exception('No hay una edición para deshacer.');
    }
    await _restoreFromSnapshot(docId, pdfPath, snapshot);
    LibraryRepository.invalidatePageCountCache(pdfPath);
    await discardUndo(docId);
    _notifyEdited(docId);
  }

  /// Elimina el punto de restauración de un documento (si existe).
  static Future<void> discardUndo(String docId) async {
    try {
      final dir = await _undoDir(docId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Warning: no se pudo borrar undo de $docId: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // INTERNOS
  // ---------------------------------------------------------------------------

  static Future<Directory> _undoDir(String docId) async {
    final docsDir = await AppData.storage.getDocsDir();
    final base = p.dirname(docsDir.path); // .../atril
    return Directory(p.join(base, _undoDirName, docId));
  }

  static Future<_UndoSnapshot> _saveUndoSnapshot(String docId, String pdfPath) async {
    final dir = await _undoDir(docId);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final snapshot = _UndoSnapshot(dir);
    await File(pdfPath).copy(snapshot.pdfPath);

    final rows = await AppData.db.getAllAnnotationStrokesForDocAllLayers(docId);
    await File(snapshot.metaPath).writeAsString(
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'strokes': rows.map((r) => r.toJson()).toList(),
      }),
      flush: true,
    );
    return snapshot;
  }

  static Future<void> _restoreFromSnapshot(
    String docId,
    String pdfPath,
    _UndoSnapshot snapshot,
  ) async {
    final bytes = await File(snapshot.pdfPath).readAsBytes();
    await _atomicWrite(pdfPath, bytes);

    final json = jsonDecode(await File(snapshot.metaPath).readAsString())
        as Map<String, dynamic>;
    final rows = (json['strokes'] as List)
        .map((m) => AnnotationStrokesTableData.fromJson(
              (m as Map).cast<String, dynamic>(),
            ))
        .toList();
    await AppData.db.replaceAnnotationsForDoc(docId, rows);
  }

  static Future<void> _atomicWrite(String path, List<int> bytes) async {
    final tempPath = '$path.tmp';
    await File(tempPath).writeAsBytes(bytes, flush: true);
    await File(tempPath).rename(path);
  }
}

class _UndoSnapshot {
  final Directory dir;
  _UndoSnapshot(this.dir);
  String get pdfPath => p.join(dir.path, PageEditRepository._undoPdfName);
  String get metaPath => p.join(dir.path, PageEditRepository._undoMetaName);
}
