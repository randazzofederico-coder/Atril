import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/data/repositories/pdf_annotation_flattener.dart';
import 'package:pdf_setlist/models/annotation_stroke.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    AppData.db = AppDatabase(executor: NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('flatten_test_');
  });

  tearDown(() async {
    await AppData.db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Crea un PDF de 2 páginas 600x800; la segunda con /Rotate 90.
  Future<String> createPdf() async {
    final doc = PdfDocument();
    doc.pageSettings.margins.all = 0;
    doc.pageSettings.size = const Size(600, 800);
    doc.pages.add();
    doc.pages.add();
    final bytes = await doc.save();
    doc.dispose();

    // Rotar la página 2 como "página cargada"
    final loaded = PdfDocument(inputBytes: bytes);
    loaded.pages[1].rotation = PdfPageRotateAngle.rotateAngle90;
    final rotated = await loaded.save();
    loaded.dispose();

    final path = '${tmp.path}/src.pdf';
    await File(path).writeAsBytes(rotated);
    return path;
  }

  AnnotationStroke stroke(String id, int page, AnnotationTool tool,
      {List<Offset> pts = const [Offset(0.1, 0.1), Offset(0.9, 0.9)],
      String? content,
      Color? color}) {
    return AnnotationStroke(
      id: id,
      docId: 'd1',
      pageIndex: page,
      tool: tool,
      width: 3,
      pointsNorm: pts,
      color: color,
      content: content,
      createdAtMs: 1,
    );
  }

  test('copia el original si el documento no tiene anotaciones', () async {
    final src = await createPdf();
    final out = '${tmp.path}/out.pdf';

    final applied = await PdfAnnotationFlattener.flattenToFile(
      docId: 'd1', sourcePath: src, outputPath: out,
    );

    expect(applied, isFalse);
    expect(await File(out).readAsBytes(), await File(src).readAsBytes());
  });

  test('aplica trazos y texto sin modificar el original', () async {
    final src = await createPdf();
    final srcBytes = await File(src).readAsBytes();
    final out = '${tmp.path}/out.pdf';

    await AnnotationRepository.insertAnnotationStroke(
        stroke('s1', 1, AnnotationTool.pen, color: const Color(0xFFFF0000)));
    await AnnotationRepository.insertAnnotationStroke(
        stroke('s2', 1, AnnotationTool.highlighter));
    await AnnotationRepository.insertAnnotationStroke(
        stroke('s3', 1, AnnotationTool.whiteout));
    await AnnotationRepository.insertAnnotationStroke(stroke(
        's4', 1, AnnotationTool.text,
        pts: const [Offset(0.5, 0.25)], content: 'Acelerando ñ'));
    await AnnotationRepository.insertAnnotationStroke(stroke(
        's5', 2, AnnotationTool.text,
        pts: const [Offset(0.1, 0.1)], content: 'Rotada'));
    // Página inexistente: debe ignorarse sin fallar
    await AnnotationRepository.insertAnnotationStroke(
        stroke('s6', 99, AnnotationTool.pen));

    final applied = await PdfAnnotationFlattener.flattenToFile(
      docId: 'd1', sourcePath: src, outputPath: out,
    );

    expect(applied, isTrue);
    // El original queda intacto
    expect(await File(src).readAsBytes(), srcBytes);

    final result = PdfDocument(inputBytes: await File(out).readAsBytes());
    expect(result.pages.count, 2);

    final extractor = PdfTextExtractor(result);
    final page1 = extractor.extractTextLines(startPageIndex: 0, endPageIndex: 0);
    final line = page1.firstWhere((l) => l.text.contains('Acelerando'));
    expect(line.text, contains('ñ'));
    // Posición: (0.5, 0.25) de una página 600x800 => (300, 200)
    expect(line.bounds.left, closeTo(300, 5));
    expect(line.bounds.top, closeTo(200, 10));

    final page2 = extractor.extractText(startPageIndex: 1, endPageIndex: 1);
    expect(page2, contains('Rotada'));

    result.dispose();
  });

  test('getAnnotatedDocIds solo considera la capa global', () async {
    await AnnotationRepository.insertAnnotationStroke(
        stroke('a', 1, AnnotationTool.pen));
    // Fila legacy de una capa por setlist (ya no se usa): no debe contarse.
    await AppData.db.insertAnnotationStroke(AnnotationStrokesTableCompanion.insert(
      id: 'b', docId: 'd2', setlistId: const Value('s1'), pageIndex: 1,
      tool: 'pen', width: 2, pointsJson: '[[0,0],[1,1]]', createdAt: 1,
    ));

    final ids = await AnnotationRepository.getAnnotatedDocIds();
    expect(ids, {'d1'});
  });
}
