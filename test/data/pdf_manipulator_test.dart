import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/repositories/pdf_manipulator.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Edición estructural: reordenar e insertar páginas de otro PDF sin pérdida.
void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('manip_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  /// PDF con una página por texto (texto real, extraíble = vectorial).
  Future<String> pdfWith(String name, List<String> texts) async {
    final doc = PdfDocument();
    doc.pageSettings.margins.all = 0;
    for (final t in texts) {
      doc.pages.add().graphics.drawString(
            t,
            PdfStandardFont(PdfFontFamily.helvetica, 24),
            bounds: const Rect.fromLTWH(50, 50, 300, 50),
          );
    }
    final path = '${tmp.path}/$name.pdf';
    await File(path).writeAsBytes(await doc.save());
    doc.dispose();
    return path;
  }

  List<String> pageTexts(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final out = [
      for (var i = 0; i < doc.pages.count; i++)
        extractor.extractText(startPageIndex: i, endPageIndex: i).trim(),
    ];
    doc.dispose();
    return out;
  }

  test('reordena e inserta páginas de otro PDF conservando el texto (sin rasterizar)', () async {
    final src = await pdfWith('src', ['A1', 'A2']);
    final ext = await pdfWith('ext', ['B1', 'B2']);

    final bytes = await PdfManipulator.applyEdits(
      sourcePdfPath: src,
      pageOrder: [
        const PageEditEntry.original(1),
        PageEditEntry.external(ext, 1),
        const PageEditEntry.original(0),
      ],
    );

    expect(pageTexts(bytes), ['A2', 'B2', 'A1']);
  });
}
