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

  group('remap / restore de anotaciones', () {
    setUp(() {
      AppData.db = AppDatabase(executor: NativeDatabase.memory());
    });
    tearDown(() async => AppData.db.close());

    Future<void> add(String id, String docId, int page, {String? setlistId}) {
      return AnnotationRepository.insertAnnotationStroke(AnnotationStroke(
        id: id,
        docId: docId,
        setlistId: setlistId,
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
      await add('c', 'd1', 3, setlistId: 's1'); // capa de setlist también se mueve
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
