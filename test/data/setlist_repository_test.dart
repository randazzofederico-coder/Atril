import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/models/setlist.dart';

/// Operaciones de setlist: memoria y DB nunca divergen.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('setlist_test_');
    AppData.storage.initForTesting(tmp);
    AppData.db = AppDatabase(executor: NativeDatabase.memory());
    for (final id in ['a', 'b', 'c']) {
      await AppData.db.upsertDoc(
        id: id, displayName: id, author: '', internalRelPath: 'docs/$id.pdf', folderId: 'root',
      );
    }
  });
  tearDown(() async {
    await AppData.db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<List<String>> dbOrder(String setlistId) async =>
      (await AppData.db.getItemsForSetlist(setlistId)).map((i) => i.docId).toList();

  List<String> memOrder(String setlistId) => AppData.getSetlistById(setlistId)!.docIds;

  test('agregar un tema repetido no rompe ni duplica', () async {
    await AppData.addSetlist(Setlist(setlistId: 's1', name: 'Show', docIds: ['a', 'a', 'b']));
    expect(await dbOrder('s1'), ['a', 'b']);
    expect(memOrder('s1'), ['a', 'b']);
  });

  test('reordenar, quitar y agregar: memoria y DB coinciden', () async {
    await AppData.addSetlist(Setlist(setlistId: 's1', name: 'Show', docIds: ['a', 'b', 'c']));

    await AppData.reorderDocInSetlist('s1', 0, 3); // 'a' al final
    expect(await dbOrder('s1'), ['b', 'c', 'a']);
    expect(memOrder('s1'), ['b', 'c', 'a']);

    await AppData.removeDocFromSetlist('s1', 'c');
    expect(await dbOrder('s1'), ['b', 'a']);
    expect(memOrder('s1'), ['b', 'a']);

    await AppData.addDocsToSetlist('s1', ['a', 'c']); // 'a' ya estaba
    expect(await dbOrder('s1'), ['b', 'a', 'c']);
    expect(memOrder('s1'), ['b', 'a', 'c']);
  });

  test('refrescar dos veces a la vez no duplica setlists en memoria', () async {
    await AppData.addSetlist(Setlist(setlistId: 's1', name: 'Show', docIds: ['a']));
    await Future.wait([AppData.refreshLibrary(), AppData.refreshLibrary()]);
    expect(AppData.setlists.where((s) => s.setlistId == 's1'), hasLength(1));
  });

  test('borrar un setlist elimina sus items', () async {
    await AppData.addSetlist(Setlist(setlistId: 's1', name: 'Show', docIds: ['a', 'b']));
    await AppData.deleteSetlist('s1');
    expect(await dbOrder('s1'), isEmpty);
    expect(AppData.getSetlistById('s1'), isNull);
  });
}
