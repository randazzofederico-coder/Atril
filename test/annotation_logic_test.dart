import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/models/annotation_stroke.dart';

/// Round-trip de serialización de anotaciones contra la clase REAL.
void main() {
  AnnotationStroke make(AnnotationTool tool,
      {List<Offset> pts = const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
      Color? color,
      String? content}) {
    return AnnotationStroke(
      id: 'id_${tool.name}',
      docId: 'd1',
      pageIndex: 3,
      tool: tool,
      width: 2.5,
      pointsNorm: pts,
      color: color,
      content: content,
      createdAtMs: 1000,
    );
  }

  test('Pen sin color usa el formato legacy (array JSON)', () {
    final item = make(AnnotationTool.pen).toDbMap();
    expect(item['tool'], 'pen');
    expect(item['points_json'], '[[0.1,0.1],[0.2,0.2]]');

    final restored = AnnotationStroke.fromDbMap(item);
    expect(restored.tool, AnnotationTool.pen);
    expect(restored.pointsNorm, const [Offset(0.1, 0.1), Offset(0.2, 0.2)]);
    expect(restored.color, isNull);
    expect(restored.pageIndex, 3);
    expect(restored.width, 2.5);
  });

  test('Trazos con color usan el formato objeto y conservan el color', () {
    for (final tool in [AnnotationTool.pen, AnnotationTool.highlighter, AnnotationTool.whiteout]) {
      final original = make(tool, color: const Color(0xFF00FF00));
      final restored = AnnotationStroke.fromDbMap(original.toDbMap());
      expect(restored.tool, tool);
      expect(restored.color!.toARGB32(), 0xFF00FF00);
      expect(restored.pointsNorm, original.pointsNorm);
    }
  });

  test('Texto y sellos conservan posición, contenido y color', () {
    final text = make(AnnotationTool.text,
        pts: const [Offset(0.5, 0.25)], content: 'Ritardando', color: const Color(0xFFFF0000));
    final r1 = AnnotationStroke.fromDbMap(text.toDbMap());
    expect(r1.tool, AnnotationTool.text);
    expect(r1.content, 'Ritardando');
    expect(r1.pointsNorm, const [Offset(0.5, 0.25)]);
    expect(r1.color!.toARGB32(), 0xFFFF0000);

    final stamp = make(AnnotationTool.stamp, pts: const [Offset(0.9, 0.1)], content: 'coda');
    final r2 = AnnotationStroke.fromDbMap(stamp.toDbMap());
    expect(r2.tool, AnnotationTool.stamp);
    expect(r2.content, 'coda');
    expect(r2.pointsNorm, const [Offset(0.9, 0.1)]);
  });

  test('JSON corrupto no rompe la lectura', () {
    final row = make(AnnotationTool.pen).toDbMap()..['points_json'] = '{{no es json';
    final restored = AnnotationStroke.fromDbMap(row);
    expect(restored.pointsNorm, isEmpty);
  });
}
