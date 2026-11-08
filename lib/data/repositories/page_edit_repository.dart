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

    final mapping = buildPageMapping(pageOrder);

    // 2. Guardar punto de restauración (PDF + anotaciones actuales + mapeo)
    final snapshot = await _saveUndoSnapshot(docId, pdfPath, mapping);

    try {
      // 3. Escribir el PDF (atómico: temp + rename)
      await _atomicWrite(pdfPath, pdfBytes);

      // 4. Reubicar anotaciones
      await AppData.db.remapAnnotationPages(docId, mapping);
    } catch (e) {
      debugPrint('Error guardando edición de páginas, restaurando: $e');
      await _restoreFromSnapshot(docId, pdfPath, snapshot, keepNewer: false);
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
    try {
      final dir = await _undoDir(docId);
      return await File(p.join(dir.path, _undoPdfName)).exists();
    } catch (_) {
      return false;
    }
  }

  /// Fecha de la última edición deshacible, o null.
  static Future<DateTime?> undoTimestamp(String docId) async {
    try {
      final meta = await _readMeta(_UndoSnapshot(await _undoDir(docId)));
      final ms = meta['savedAt'] as int?;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Cuántas anotaciones hechas DESPUÉS de la edición se perderían al
  /// deshacerla (las que están en páginas que la edición agregó y que, por
  /// lo tanto, dejan de existir). 0 = deshacer no pierde nada.
  static Future<int> undoWouldLoseAnnotations(String docId) async {
    try {
      final snapshot = _UndoSnapshot(await _undoDir(docId));
      final meta = await _readMeta(snapshot);
      final current = await AppData.db.getAllAnnotationStrokesForDocAllLayers(docId);
      return mergeAnnotationsForUndo(
        snapshotRows: _snapshotRows(meta),
        currentRows: current,
        pageMapping: _snapshotMapping(meta),
      ).lost;
    } catch (_) {
      return 0;
    }
  }

  /// Restaura el PDF al estado previo a la última edición de páginas guardada.
  ///
  /// Las anotaciones se combinan (ver [mergeAnnotationsForUndo]): vuelven las
  /// borradas por la edición y las hechas después se reubican en su página
  /// original. Luego se descarta el punto de restauración.
  static Future<void> undoLastEdit({required String docId, required String pdfPath}) async {
    final dir = await _undoDir(docId);
    final snapshot = _UndoSnapshot(dir);
    if (!await File(snapshot.pdfPath).exists()) {
      throw Exception('No hay una edición para deshacer.');
    }
    await _restoreFromSnapshot(docId, pdfPath, snapshot, keepNewer: true);
    LibraryRepository.invalidatePageCountCache(pdfPath);
    await discardUndo(docId);
    _notifyEdited(docId);
  }

  /// Combina las anotaciones al deshacer una edición de páginas.
  ///
  /// - [snapshotRows]: anotaciones ANTES de la edición (páginas viejas).
  /// - [currentRows]: anotaciones AHORA (páginas nuevas, incluidas las hechas
  ///   después de la edición).
  /// - [pageMapping]: página vieja → página nueva de esa edición. Si es null
  ///   (puntos de restauración antiguos), las anotaciones nuevas no se pueden
  ///   reubicar y cuentan como perdidas.
  ///
  /// Resultado:
  /// - Anotaciones de páginas que la edición ELIMINÓ: vuelven.
  /// - Anotaciones previas que siguen existiendo: vuelven a su página vieja.
  ///   Si el usuario las borró después de la edición, siguen borradas.
  /// - Anotaciones nuevas en páginas originales: se mueven a la página vieja.
  /// - Anotaciones nuevas en páginas agregadas por la edición: se pierden
  ///   (esas páginas dejan de existir) → se informan en `lost`.
  static ({List<AnnotationStrokesTableData> rows, int lost}) mergeAnnotationsForUndo({
    required List<AnnotationStrokesTableData> snapshotRows,
    required List<AnnotationStrokesTableData> currentRows,
    required Map<int, int>? pageMapping,
  }) {
    final currentIds = {for (final r in currentRows) r.id};
    final snapshotIds = {for (final r in snapshotRows) r.id};
    final inverse = <int, int>{
      if (pageMapping != null)
        for (final e in pageMapping.entries) e.value: e.key,
    };

    final result = <AnnotationStrokesTableData>[];
    for (final r in snapshotRows) {
      final survivedEdit = pageMapping?.containsKey(r.pageIndex) ?? false;
      if (!survivedEdit || currentIds.contains(r.id)) {
        result.add(r);
      }
    }

    var lost = 0;
    for (final r in currentRows) {
      if (snapshotIds.contains(r.id)) continue; // ya contemplada arriba
      final oldPage = inverse[r.pageIndex];
      if (oldPage == null) {
        lost++;
      } else {
        result.add(r.copyWith(pageIndex: oldPage));
      }
    }
    return (rows: result, lost: lost);
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

  /// Elimina TODOS los puntos de restauración (p. ej. al restaurar un backup,
  /// donde dejan de corresponder a los PDFs actuales).
  static Future<void> discardAllUndo() async {
    try {
      final docsDir = await AppData.storage.getDocsDir();
      final dir = Directory(p.join(p.dirname(docsDir.path), _undoDirName));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Warning: no se pudieron borrar los puntos de restauración: $e');
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

  static Future<_UndoSnapshot> _saveUndoSnapshot(
    String docId,
    String pdfPath,
    Map<int, int> mapping,
  ) async {
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
        'pageMapping': {for (final e in mapping.entries) '${e.key}': e.value},
      }),
      flush: true,
    );
    return snapshot;
  }

  static Future<Map<String, dynamic>> _readMeta(_UndoSnapshot snapshot) async {
    return jsonDecode(await File(snapshot.metaPath).readAsString()) as Map<String, dynamic>;
  }

  static List<AnnotationStrokesTableData> _snapshotRows(Map<String, dynamic> meta) {
    return (meta['strokes'] as List)
        .map((m) => AnnotationStrokesTableData.fromJson((m as Map).cast<String, dynamic>()))
        .toList();
  }

  static Map<int, int>? _snapshotMapping(Map<String, dynamic> meta) {
    final raw = meta['pageMapping'];
    if (raw is! Map) return null;
    return {
      for (final e in raw.entries) int.parse(e.key as String): (e.value as num).toInt(),
    };
  }

  /// Restaura PDF y anotaciones desde un punto de restauración.
  ///
  /// [keepNewer]: si es true (deshacer), conserva las anotaciones hechas
  /// después de la edición. Si es false (rollback inmediato tras un error al
  /// guardar), vuelve exactamente al snapshot.
  static Future<void> _restoreFromSnapshot(
    String docId,
    String pdfPath,
    _UndoSnapshot snapshot, {
    required bool keepNewer,
  }) async {
    final meta = await _readMeta(snapshot);
    final snapshotRows = _snapshotRows(meta);

    final List<AnnotationStrokesTableData> rows;
    if (keepNewer) {
      final current = await AppData.db.getAllAnnotationStrokesForDocAllLayers(docId);
      rows = mergeAnnotationsForUndo(
        snapshotRows: snapshotRows,
        currentRows: current,
        pageMapping: _snapshotMapping(meta),
      ).rows;
    } else {
      rows = snapshotRows;
    }

    // PDF: copia + rename (sin cargar todo el archivo en memoria)
    final tempPath = '$pdfPath.tmp';
    await File(snapshot.pdfPath).copy(tempPath);
    await File(tempPath).rename(pdfPath);

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
