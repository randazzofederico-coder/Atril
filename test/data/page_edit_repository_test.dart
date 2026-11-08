import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/data/repositories/page_edit_repository.dart';
import 'package:pdf_setlist/data/repositories/pdf_manipulator.dart';
import 'package:pdf_setlist/models/annotation_stroke.dart';

void main() {
  group('buildPageMapping', () {
    test('reordenar, eliminar e insertar páginas', () {
      // Original: 4 páginas (0..3). Nuevo orden:
      // [orig 2, imagen, orig 0, orig 3]  => orig 1 eliminada
      final order = [
        const PageEditEntry.original(2),
        const PageEditEntry.image('/tmp/x.jpg'),
        const PageEditEntry.original(0),
        const PageEditEntry.original(3),
      ];

      final m = PageEditRepository.buildPageMapping(order);

      expect(m, {3: 1, 1: 3, 4: 4}); // 1-based
      expect(m.containsKey(2), isFalse); // eliminada
    });

    test('sin cambios = identidad', () {
      final order = List.generate(3, (i) => PageEditEntry.original(i));
      expect(PageEditRepository.buildPageMapping(order), {1: 1, 2: 2, 3: 3});
    });
  });

  group('mergeAnnotationsForUndo (deshacer edición sin perder anotaciones)', () {
    AnnotationStrokesTableData row(String id, int page, {int createdAt = 1}) =>
        AnnotationStrokesTableData(
          id: id, docId: 'd1', pageIndex: page, tool: 'pen', width: 2,
          pointsJson: '[]', createdAt: createdAt,
        );

    Map<String, int> pages(List<AnnotationStrokesTableData> rows) =>
        {for (final r in rows) r.id: r.pageIndex};

    // Edición: 3 páginas originales → [orig 2, nueva, orig 0]  (orig 1 eliminada)
    // mapping viejo→nuevo: 3→1, 1→3   (página 2 eliminada, página 2 nueva = agregada)
    const mapping = {3: 1, 1: 3};

    test('vuelven las borradas por la edición y las previas a su página vieja', () {
      final snapshot = [row('a', 1), row('b', 2), row('c', 3)];
      final current = [row('a', 3), row('c', 1)]; // 'b' la borró la edición
      final r = PageEditRepository.mergeAnnotationsForUndo(
        snapshotRows: snapshot, currentRows: current, pageMapping: mapping,
      );
      expect(pages(r.rows), {'a': 1, 'b': 2, 'c': 3});
      expect(r.lost, 0);
    });

    test('anotaciones hechas DESPUÉS se conservan en su página original', () {
      final snapshot = [row('a', 1)];
      final current = [row('a', 3), row('nueva', 1, createdAt: 99)]; // en orig 3
      final r = PageEditRepository.mergeAnnotationsForUndo(
        snapshotRows: snapshot, currentRows: current, pageMapping: mapping,
      );
      expect(pages(r.rows), {'a': 1, 'nueva': 3});
      expect(r.lost, 0);
    });

    test('las hechas en páginas AGREGADAS por la edición se informan como perdidas', () {
      final current = [row('enPaginaNueva', 2, createdAt: 99)];
      final r = PageEditRepository.mergeAnnotationsForUndo(
        snapshotRows: const [], currentRows: current, pageMapping: mapping,
      );
      expect(r.rows, isEmpty);
      expect(r.lost, 1);
    });

    test('si el usuario borró una anotación después de la edición, no revive', () {
      final snapshot = [row('a', 1)];
      final r = PageEditRepository.mergeAnnotationsForUndo(
        snapshotRows: snapshot, currentRows: const [], pageMapping: mapping,
      );
      expect(r.rows, isEmpty);
    });
  });

  group('remap / restore de anotaciones', () {
    setUp(() {
      AppData.db = AppDatabase(executor: NativeDatabase.memory());
    });
    tearDown(() async => AppData.db.close());

    Future<void> add(String id, String docId, int page) {
      return AnnotationRepository.insertAnnotationStroke(AnnotationStroke(
        id: id,
        docId: docId,
        pageIndex: page,
        tool: AnnotationTool.pen,
        width: 2,
        pointsNorm: const [Offset(0, 0), Offset(1, 1)],
        createdAtMs: 1,
      ));
    }

    Future<Map<String, int>> pagesOf(String docId) async {
      final rows = await AppData.db.getAllAnnotationStrokesForDocAllLayers(docId);
      return {for (final r in rows) r.id: r.pageIndex};
    }

    test('las anotaciones siguen a sus páginas y se borran con las eliminadas', () async {
      await add('a', 'd1', 1);
      await add('b', 'd1', 2);
      await add('c', 'd1', 3);
      await add('d', 'd1', 4);
      await add('other', 'd2', 2); // otro documento: no se toca

      final mapping = PageEditRepository.buildPageMapping([
        const PageEditEntry.original(2),
        const PageEditEntry.image('/tmp/x.jpg'),
        const PageEditEntry.original(0),
        const PageEditEntry.original(3),
      ]);
      await AppData.db.remapAnnotationPages('d1', mapping);

      expect(await pagesOf('d1'), {'a': 3, 'c': 1, 'd': 4}); // 'b' eliminada
      expect(await pagesOf('d2'), {'other': 2});
    });

    test('deshacer restaura exactamente el estado anterior', () async {
      await add('a', 'd1', 1);
      await add('b', 'd1', 2);
      final snapshot = await AppData.db.getAllAnnotationStrokesForDocAllLayers('d1');

      await AppData.db.remapAnnotationPages('d1', {2: 1}); // borra 'a', mueve 'b'
      expect(await pagesOf('d1'), {'b': 1});

      await AppData.db.replaceAnnotationsForDoc('d1', snapshot);
      expect(await pagesOf('d1'), {'a': 1, 'b': 2});
    });
  });
}
