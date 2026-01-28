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
/// - v2 adds whiteout, text, and stamps.
/// - Future: setlist-specific layer by setting [setlistId] non-null.
enum AnnotationTool {
  pen,
  highlighter,
  whiteout,
  text,
  stamp,
}

class AnnotationStroke {
  final String id;
  final String docId;
  final String? setlistId;
  final int pageIndex; // 1-based, consistent with PdfViewPinch
  final AnnotationTool tool;
  final double width;
  
  // For Strokes (pen, highlighter, whiteout):
  final List<Offset> pointsNorm; // normalized points [0..1]
  
  // For Text/Stamps:
  final Color? color;     // Explicit color support
  final String? content;  // "Some Text" or "CODE_CODA"

  final int createdAtMs;

  const AnnotationStroke({
    required this.id,
    required this.docId,
    required this.setlistId,
    required this.pageIndex,
    required this.tool,
    required this.width,
    this.pointsNorm = const [],
    this.color,
    this.content,
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
      'points_json': _encodeData(),
      'created_at': createdAtMs,
    };
  }

  static AnnotationStroke fromDbMap(Map<String, Object?> row) {
    final tool = toolFromName(row['tool'] as String);
    final rawJson = row['points_json'] as String;
    
    // Default values
    List<Offset> pts = const [];
    Color? col;
    String? txt;

    if (tool == AnnotationTool.text || tool == AnnotationTool.stamp) {
      // Decode Object
      try {
        final map = jsonDecode(rawJson);
        if (map is Map<String, dynamic>) {
           // x, y are stored as a single point in pointsNorm for convenience
           final x = (map['x'] as num? ?? 0).toDouble();
           final y = (map['y'] as num? ?? 0).toDouble();
           pts = [Offset(x, y)];
           
           if (map.containsKey('color')) col = Color(map['color'] as int);
           txt = map['content'] as String?;
        }
      } catch (_) { /* ignore corruption */ }
    } else {
      // Decode Array (Legacy Strokes)
      pts = _decodePoints(rawJson);
      // Try to recover color if stored in future/legacy versions?? 
      // Current v1 had hardcoded colors in painter.
    }

    return AnnotationStroke(
      id: row['id'] as String,
      docId: row['doc_id'] as String,
      setlistId: row['setlist_id'] as String?,
      pageIndex: (row['page_index'] as int),
      tool: tool,
      width: (row['width'] as num).toDouble(),
      pointsNorm: pts,
      color: col,
      content: txt,
      createdAtMs: (row['created_at'] as int),
    );
  }

  // ---------------- Serialization helpers ----------------

  static String encodePoints(List<Offset> pts) {
    // Legacy support: Only for array based strokes. 
    // New logic uses _encodeData internally, but this is kept for Repository compatibility if needed
    final arr = pts.map((p) => [p.dx, p.dy]).toList(growable: false);
    return jsonEncode(arr);
  }

  static List<Offset> decodePoints(String jsonStr) {
    return _decodePoints(jsonStr);
  }

  String _encodeData() {
    if (tool == AnnotationTool.text || tool == AnnotationTool.stamp) {
      // Store as object
      final p = pointsNorm.isNotEmpty ? pointsNorm.first : Offset.zero;
      final map = <String, dynamic>{
        'x': p.dx,
        'y': p.dy,
        'content': content ?? '',
      };
      if (color != null) map['color'] = color!.toARGB32();
      return jsonEncode(map);
    } else {
      // Store as array (Backward compatibility for strokes)
      return encodePoints(pointsNorm);
    }
  }

  static List<Offset> _decodePoints(String jsonStr) {
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
