import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';

/// Importar un archivo .setlist recibido (formato atril_setlist_v1).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('setlist_import_test_');
    final tempForApp = Directory('${tmp.path}/temp')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempForApp.path,
    );
    AppData.storage.initForTesting(Directory('${tmp.path}/atril'));
    AppData.db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await AppData.db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> buildSetlist(List<Map<String, dynamic>> items, Map<String, String> pdfs) async {
    final src = Directory('${tmp.path}/src')..createSync();
    final data = File('${src.path}/data.json')
      ..writeAsStringSync(jsonEncode({
        'format': 'atril_setlist_v1',
        'version': 1,
        'setlistName': 'Boda',
        'items': items,
      }));
    final path = '${tmp.path}/boda.setlist';
    final enc = ZipFileEncoder()..create(path);
    await enc.addFile(data, 'data.json');
    for (final e in pdfs.entries) {
      final f = File('${src.path}/${e.key}')..writeAsStringSync(e.value);
      await enc.addFile(f, e.key);
    }
    enc.close();
    return path;
  }

  test('crea carpeta, partituras, anotaciones y setlist en orden', () async {
    final path = await buildSetlist([
      {
        'index': 0, 'title': 'Primero', 'author': 'A', 'filename': 'x1.pdf',
        'annotations': [
          {'page_index': 1, 'tool': 'pen', 'width': 2.0, 'points_json': '[[0,0],[1,1]]', 'created_at': 1},
        ],
      },
      {'index': 1, 'title': 'Segundo', 'author': 'B', 'filename': 'x2.pdf'},
      // Nombre malicioso: se ignora
      {'index': 2, 'title': 'Malo', 'author': '', 'filename': '../atril.sqlite'},
    ], {'x1.pdf': '%PDF 1', 'x2.pdf': '%PDF 2'});

    final setlistId = await AppData.importSetlistFile(path);

    final setlist = AppData.getSetlistById(setlistId!)!;
    expect(setlist.name, 'Boda');
    final titles = setlist.docIds.map((id) => AppData.getScoreById(id)!.title).toList();
    expect(titles, ['Primero', 'Segundo']);

    final first = setlist.docIds.first;
    expect(await AppData.db.getAllAnnotationStrokesForDocAllLayers(first), hasLength(1));

    final folder = AppData.folders.singleWhere((f) => f.name == 'Boda');
    expect(AppData.library.every((s) => s.folderId == folder.id), isTrue);
  });

  test('si no hay ningún PDF válido no deja carpetas ni partituras', () async {
    final path = await buildSetlist([
      {'index': 0, 'title': 'Falta', 'author': '', 'filename': 'noexiste.pdf'},
    ], {});

    await expectLater(AppData.importSetlistFile(path), throwsException);
    expect(await AppData.db.getAllDocs(), isEmpty);
    expect((await AppData.db.getAllFolders()).where((f) => f.id != 'root'), isEmpty);
  });
}
