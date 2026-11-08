import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_database.dart';

void main() {
  test('migración v4 → v5: purga anotaciones huérfanas y crea índices', () async {
    final dir = await Directory.systemTemp.createTemp('mig_test_');
    final file = File('${dir.path}/atril.sqlite');

    // 1. Base "v4" con una anotación válida y una huérfana
    final db1 = AppDatabase(executor: NativeDatabase(file));
    await db1.upsertDoc(
      id: 'd1', displayName: 'Tema', author: '', internalRelPath: 'docs/d1.pdf', folderId: 'root',
    );
    for (final (id, doc) in [('ok', 'd1'), ('huerfana', 'borrado')]) {
      await db1.insertAnnotationStroke(AnnotationStrokesTableCompanion.insert(
        id: id, docId: doc, setlistId: const Value(null), pageIndex: 1,
        tool: 'pen', width: 2, pointsJson: '[]', createdAt: 1,
      ));
    }
    await db1.customStatement('DROP INDEX IF EXISTS idx_strokes_doc_page');
    await db1.customStatement('DROP INDEX IF EXISTS idx_setlist_items_doc');
    await db1.customStatement('PRAGMA user_version = 4');
    await db1.close();

    // 2. Reabrir: corre la migración a v5
    final db2 = AppDatabase(executor: NativeDatabase(file));
    final strokes = await db2.getAllAnnotationStrokes();
    expect(strokes.map((s) => s.id), ['ok']);

    final idx = await db2
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final names = idx.map((r) => r.data['name']).toSet();
    expect(names, containsAll(['idx_strokes_doc_page', 'idx_setlist_items_doc']));

    // El documento y su anotación siguen intactos
    expect(await db2.getDocById('d1'), isNotNull);
    await db2.close();
    await dir.delete(recursive: true);
  });
}
