import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:ui';
// Mocking the class structure since we can't easily import from lib in a standalone script without full flutter environment context usually, 
// but here we will try to replicate the logic or rely on the agent to run it in a way that works.
// Actually, I'll write a standalone dart script that copies the relevant class logic for verification to ensure the logic itself holds up.

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
  final int pageIndex;
  final AnnotationTool tool;
  final double width;
  final List<Offset> pointsNorm;
  final Color? color;
  final String? content;
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
    
    List<Offset> pts = const [];
    Color? col;
    String? txt;

    if (tool == AnnotationTool.text || tool == AnnotationTool.stamp) {
      try {
        final map = jsonDecode(rawJson);
        if (map is Map<String, dynamic>) {
           final x = (map['x'] as num? ?? 0).toDouble();
           final y = (map['y'] as num? ?? 0).toDouble();
           pts = [Offset(x, y)];
           
           if (map.containsKey('color')) col = Color(map['color'] as int);
           txt = map['content'] as String?;
        }
      } catch (_) { }
    } else {
      pts = _decodePoints(rawJson);
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

  String _encodeData() {
    if (tool == AnnotationTool.text || tool == AnnotationTool.stamp) {
      final p = pointsNorm.isNotEmpty ? pointsNorm.first : Offset.zero;
      final map = <String, dynamic>{
        'x': p.dx,
        'y': p.dy,
        'content': content ?? '',
      };
      if (color != null) map['color'] = color!.toARGB32();
      return jsonEncode(map);
    } else {
      final arr = pointsNorm.map((p) => [p.dx, p.dy]).toList(growable: false);
      return jsonEncode(arr);
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

void main() {
  test('AnnotationStroke Persistence - Pen (Array JSON)', () {
    final original = AnnotationStroke(
      id: '1', docId: 'd1', setlistId: null, pageIndex: 1,
      tool: AnnotationTool.pen, width: 2.0,
      pointsNorm: [const Offset(0.1, 0.1), const Offset(0.2, 0.2)],
      createdAtMs: 1000,
    );

    final item = original.toDbMap();
    expect(item['tool'], 'pen');
    final json = item['points_json'] as String;
    expect(json, contains('[[0.1,0.1],[0.2,0.2]]'));

    final restored = AnnotationStroke.fromDbMap(item);
    expect(restored.tool, AnnotationTool.pen);
    expect(restored.pointsNorm.length, 2);
    expect(restored.pointsNorm.first.dx, 0.1);
  });

  test('AnnotationStroke Persistence - Text (Object JSON)', () {
    final original = AnnotationStroke(
      id: '2', docId: 'd1', setlistId: null, pageIndex: 1,
      tool: AnnotationTool.text, width: 1.0,
      pointsNorm: [const Offset(0.5, 0.5)],
      content: 'Hello',
      color: const Color(0xFFFF0000),
      createdAtMs: 2000,
    );

    final item = original.toDbMap();
    expect(item['tool'], 'text');
    final json = item['points_json'] as String;
    expect(json, contains('"content":"Hello"'));
    expect(json, contains('"x":0.5'));

    final restored = AnnotationStroke.fromDbMap(item);
    expect(restored.tool, AnnotationTool.text);
    expect(restored.content, 'Hello');
    expect(restored.color!.toARGB32(), 0xFFFF0000);
    expect(restored.pointsNorm.length, 1);
  });
}
