import 'dart:convert';
import 'dart:ui';

/// Basic non-destructive PDF annotation model.
///
/// Coordinates are stored NORMALIZED to the page viewport:
/// - dx, dy in [0..1] relative to the rendered page area.
/// This makes annotations stable across devices/resolutions.
///
/// Notes:
/// - v1 supports only freehand strokes (pen/highlighter).
/// - Future: setlist-specific layer by setting [setlistId] non-null.
enum AnnotationTool {
  pen,
  highlighter,
}

class AnnotationStroke {
  final String id;
  final String docId;
  final String? setlistId;
  final int pageIndex; // 1-based, consistent with PdfViewPinch
  final AnnotationTool tool;
  final double width;
  final List<Offset> pointsNorm; // normalized points [0..1]
  final int createdAtMs;

  const AnnotationStroke({
    required this.id,
    required this.docId,
    required this.setlistId,
    required this.pageIndex,
    required this.tool,
    required this.width,
    required this.pointsNorm,
    required this.createdAtMs,
  });

  String get toolName => tool.name;

  static AnnotationTool toolFromName(String name) {
    return AnnotationTool.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AnnotationTool.pen,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'doc_id': docId,
      'setlist_id': setlistId,
      'page_index': pageIndex,
      'tool': toolName,
      'width': width,
      'points_json': encodePoints(pointsNorm),
      'created_at': createdAtMs,
    };
  }

  static AnnotationStroke fromDbMap(Map<String, Object?> row) {
    return AnnotationStroke(
      id: row['id'] as String,
      docId: row['doc_id'] as String,
      setlistId: row['setlist_id'] as String?,
      pageIndex: (row['page_index'] as int),
      tool: toolFromName(row['tool'] as String),
      width: (row['width'] as num).toDouble(),
      pointsNorm: decodePoints(row['points_json'] as String),
      createdAtMs: (row['created_at'] as int),
    );
  }

  // ---------------- Serialization helpers ----------------

  /// Encodes points as JSON: [[x,y], ...]
  static String encodePoints(List<Offset> pts) {
    final arr = pts.map((p) => [p.dx, p.dy]).toList(growable: false);
    return jsonEncode(arr);
  }

  static List<Offset> decodePoints(String jsonStr) {
    try {
      final raw = jsonDecode(jsonStr);
      if (raw is! List) return const <Offset>[];
      final out = <Offset>[];
      for (final e in raw) {
        if (e is List && e.length >= 2) {
          final dx = (e[0] as num).toDouble();
          final dy = (e[1] as num).toDouble();
          out.add(Offset(dx, dy));
        }
      }
      return out;
    } catch (_) {
      return const <Offset>[];
    }
  }
}
