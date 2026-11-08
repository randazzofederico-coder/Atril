import 'package:drift/drift.dart';
import '../../models/annotation_stroke.dart';
import '../app_database.dart'; // To access table data classes
import '../app_data.dart';

/// Acceso a las anotaciones (una capa global por documento).
///
/// Nota: la tabla conserva la columna `setlist_id` por compatibilidad con
/// datos viejos, pero la app ya no crea ni muestra capas por setlist: todas
/// las lecturas filtran `setlist_id IS NULL` y las escrituras lo dejan en null.
class AnnotationRepository {

  /// Convierte una fila de Drift al modelo de dominio.
  static AnnotationStroke fromRow(AnnotationStrokesTableData r) {
    return AnnotationStroke.fromDbMap({
      'id': r.id,
      'doc_id': r.docId,
      'page_index': r.pageIndex,
      'tool': r.tool,
      'width': r.width,
      'points_json': r.pointsJson,
      'created_at': r.createdAt,
    });
  }

  /// Todos los trazos de un documento, todas las páginas.
  static Future<List<AnnotationStroke>> getAnnotationStrokesForDoc(String docId) async {
    final rows = await AppData.db.getAnnotationStrokesForDoc(docId: docId);
    return rows.map(fromRow).toList();
  }

  /// IDs de documentos que tienen anotaciones.
  static Future<Set<String>> getAnnotatedDocIds() => AppData.db.getAnnotatedDocIds();
  
  static Future<List<AnnotationStroke>> getAnnotationStrokesForPage({
    required String docId, 
    required int pageIndex, 
  }) async {
    final rows = await AppData.db.getAnnotationStrokes(
      docId: docId, 
      pageIndex: pageIndex, 
    );
    return rows.map(fromRow).toList();
  }

  static Future<void> insertAnnotationStroke(AnnotationStroke s) async {
    await AppData.db.insertAnnotationStroke(
      AnnotationStrokesTableCompanion(
        id: Value(s.id),
        docId: Value(s.docId),
        setlistId: const Value(null),
        pageIndex: Value(s.pageIndex),
        tool: Value(s.toolName),
        width: Value(s.width),
        pointsJson: Value(s.encodedPointsJson),
        createdAt: Value(s.createdAtMs),
      )
    );
  }

  static Future<void> deleteAnnotationStroke(String id) async {
    await AppData.db.deleteAnnotationStrokeById(id);
  }

  static Future<void> deleteAnnotationStrokesForPage({
    required String docId, 
    required int pageIndex, 
  }) async {
    await AppData.db.deleteAnnotationStrokesForPage(
      docId: docId, 
      pageIndex: pageIndex, 
    );
  }
}
