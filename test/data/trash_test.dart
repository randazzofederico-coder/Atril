import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/models/annotation_stroke.dart';

/// Papelera: restaurar y purgar nunca deben perder documentos activos.
void main() {
  setUp(() {
    AppData.db = AppDatabase(executor: NativeDatabase.memory());
  });
  tearDown(() async => AppData.db.close());

  Future<void> folder(String id, {String? parent}) =>
      AppData.db.createFolder(id: id, name: id, parentId: parent);

  Future<void> doc(String id, String folderId) => AppData.db.upsertDoc(
        id: id,
        displayName: id,
        author: '',
        internalRelPath: 'docs/$id.pdf',
        folderId: folderId,
      );

  Future<DocsTableData?> getDoc(String id) => AppData.db.getDocById(id);

  test('restaurar un doc cuya carpeta sigue en la papelera lo lleva a la raíz', () async {
    await folder('f1');
    await doc('d1', 'f1');
    await AppData.db.softDeleteDoc('d1');
    await AppData.db.softDeleteFolder('f1');

    await LibraryRepository.restoreItems(docIds: ['d1'], folderIds: []);

    final d1 = await getDoc('d1');
    expect(d1!.isDeleted, isFalse);
    expect(d1.folderId, 'root');

    // Y al purgar la carpeta, el doc restaurado sigue vivo.
    await LibraryRepository.permanentlyDeleteItems(docIds: [], folderIds: ['f1']);
    expect(await getDoc('d1'), isNotNull);
    expect(await AppData.db.getFolderById('f1'), isNull);
  });

  test('purgar una carpeta rescata documentos y subcarpetas activos', () async {
    await folder('f1');
    await folder('sub', parent: 'f1');
    await doc('activo', 'f1');
    await doc('borrado', 'f1');
    await AppData.db.softDeleteDoc('borrado');
    await AppData.db.softDeleteFolder('f1'); // 'activo' y 'sub' quedaron activos

    await LibraryRepository.permanentlyDeleteItems(docIds: [], folderIds: ['f1']);

    final activo = await getDoc('activo');
    expect(activo, isNotNull);
    expect(activo!.folderId, 'root');
    expect(await getDoc('borrado'), isNull);
    final sub = await AppData.db.getFolderById('sub');
    expect(sub, isNotNull);
    expect(sub!.parentId, isNull);
  });

  test('nunca se purga un documento activo aunque se pida', () async {
    await doc('d1', 'root');
    await LibraryRepository.permanentlyDeleteItems(docIds: ['d1'], folderIds: []);
    expect(await getDoc('d1'), isNotNull);
  });

  test('purgar un doc borra sus anotaciones e items de setlist', () async {
    await doc('d1', 'root');
    await doc('d2', 'root');
    await AppData.db.upsertSetlist(id: 's1', name: 'Show');
    await AppData.db.replaceSetlistItems(setlistId: 's1', orderedDocIds: ['d1', 'd2']);
    for (final d in ['d1', 'd2']) {
      await AnnotationRepository.insertAnnotationStroke(AnnotationStroke(
        id: 'stk_$d', docId: d, pageIndex: 1, tool: AnnotationTool.pen, width: 2,
        pointsNorm: const [Offset(0, 0), Offset(1, 1)], createdAtMs: 1,
      ));
    }

    await AppData.db.softDeleteDoc('d1');
    await LibraryRepository.permanentlyDeleteItems(docIds: ['d1'], folderIds: []);

    expect(await getDoc('d1'), isNull);
    expect(await AppData.db.getAllAnnotationStrokesForDocAllLayers('d1'), isEmpty);
    expect(await AppData.db.getAllAnnotationStrokesForDocAllLayers('d2'), hasLength(1));
    final items = await AppData.db.getItemsForSetlist('s1');
    expect(items.map((i) => i.docId), ['d2']);
  });

  test('restaurar una subcarpeta cuyo padre sigue borrado la lleva a la raíz', () async {
    await folder('padre');
    await folder('hija', parent: 'padre');
    await doc('d1', 'hija');
    await AppData.db.softDeleteDoc('d1');
    await AppData.db.softDeleteFolder('hija');
    await AppData.db.softDeleteFolder('padre');

    await LibraryRepository.restoreItems(docIds: [], folderIds: ['hija']);

    final hija = await AppData.db.getFolderById('hija');
    expect(hija!.isDeleted, isFalse);
    expect(hija.parentId, isNull);
    expect((await getDoc('d1'))!.isDeleted, isFalse);
    expect((await getDoc('d1'))!.folderId, 'hija');
  });
}
