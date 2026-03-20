import 'package:drift/drift.dart';
import '../../models/annotation_stroke.dart';
import '../app_database.dart'; // To access table data classes
import '../app_data.dart';

class AnnotationRepository {
  
  static Future<List<AnnotationStroke>> getAnnotationStrokesForPage({
    required String docId, 
    required int pageIndex, 
    String? setlistId
  }) async {
    final rows = await AppData.db.getAnnotationStrokes(
      docId: docId, 
      pageIndex: pageIndex, 
      setlistId: setlistId
    );
    return rows.map((r) => AnnotationStroke.fromDbMap({
      'id': r.id,
      'doc_id': r.docId,
      'setlist_id': r.setlistId,
      'page_index': r.pageIndex,
      'tool': r.tool,
      'width': r.width,
      'points_json': r.pointsJson,
      'created_at': r.createdAt,
    })).toList();
  }

  static Future<void> insertAnnotationStroke(AnnotationStroke s) async {
    await AppData.db.insertAnnotationStroke(
      AnnotationStrokesTableCompanion(
        id: Value(s.id),
        docId: Value(s.docId),
        setlistId: Value(s.setlistId),
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
    String? setlistId
  }) async {
    await AppData.db.deleteAnnotationStrokesForPage(
      docId: docId, 
      pageIndex: pageIndex, 
      setlistId: setlistId
    );
  }
}