import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/data/backup_manager.dart';

/// "Importar Backup" (merge) de punta a punta con un .atril armado a mano.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_test_');
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

  /// Arma un .atril con: carpeta "Jazz" > "Standards" > doc d1 (con PDF y
  /// anotación), doc d2 sin PDF, y un setlist [d1, d2].
  Future<String> buildBackup() async {
    final src = Directory('${tmp.path}/src')..createSync();
    final dbFile = File('${src.path}/atril.sqlite');
    final db = AppDatabase(executor: NativeDatabase(dbFile));
    await db.createFolder(id: 'jazz', name: 'Jazz', parentId: null);
    await db.createFolder(id: 'std', name: 'Standards', parentId: 'jazz');
    await db.upsertDoc(id: 'd1', displayName: 'Autumn Leaves', author: 'Kosma',
        internalRelPath: 'docs/d1.pdf', folderId: 'std');
    await db.upsertDoc(id: 'd2', displayName: 'Sin archivo', author: '',
        internalRelPath: 'docs/d2.pdf', folderId: 'jazz');
    await db.insertAnnotationStroke(AnnotationStrokesTableCompanion.insert(
      id: 'stk1', docId: 'd1', setlistId: const Value(null), pageIndex: 2,
      tool: 'pen', width: 3, pointsJson: '[[0.1,0.1],[0.2,0.2]]', createdAt: 5,
    ));
    await db.upsertSetlist(id: 's1', name: 'Show');
    await db.replaceSetlistItems(setlistId: 's1', orderedDocIds: ['d1', 'd2']);
    await db.close();

    final pdf = File('${src.path}/d1.pdf')..writeAsStringSync('%PDF-1.4 fake');
    final zipPath = '${tmp.path}/backup.atril';
    final enc = ZipFileEncoder()..create(zipPath);
    await enc.addFile(dbFile, 'atril.sqlite');
    await enc.addFile(pdf, 'docs/d1.pdf');
    enc.close();
    return zipPath;
  }

  test('importa carpetas, partituras, anotaciones y setlists', () async {
    final zip = await buildBackup();

    final report = await BackupManager.instance.importBackup(zip);

    expect(report.docs, 1);
    expect(report.missingFiles, 1);
    expect(report.annotations, 1);
    expect(report.setlists, 1);

    final docs = await AppData.db.getAllDocs();
    expect(docs, hasLength(1));
    final d = docs.single;
    expect(d.displayName, 'Autumn Leaves');
    expect(d.author, 'Kosma');
    expect(File(AppData.storage.absPathFromRelPath(d.internalRelPath)).existsSync(), isTrue);

    // Jerarquía: Backup Importado > Jazz > Standards > doc
    final folders = await AppData.db.getAllFolders();
    final std = folders.firstWhere((f) => f.name == 'Standards');
    final jazz = folders.firstWhere((f) => f.name == 'Jazz');
    final rootImport = folders.firstWhere((f) => f.name.startsWith('Backup Importado'));
    expect(d.folderId, std.id);
    expect(std.parentId, jazz.id);
    expect(jazz.parentId, rootImport.id);

    final strokes = await AppData.db.getAllAnnotationStrokesForDocAllLayers(d.id);
    expect(strokes.single.pageIndex, 2);

    expect(AppData.setlists.single.name, 'Show');
    expect(AppData.setlists.single.docIds, [d.id]);
  });

  test('un backup inválido no deja nada a medias', () async {
    final bad = File('${tmp.path}/bad.atril');
    final enc = ZipFileEncoder()..create(bad.path);
    final junk = File('${tmp.path}/x.txt')..writeAsStringSync('hola');
    await enc.addFile(junk, 'x.txt');
    enc.close();

    await expectLater(BackupManager.instance.importBackup(bad.path), throwsException);
    expect(await AppData.db.getAllDocs(), isEmpty);
    expect((await AppData.db.getAllFolders()).where((f) => f.id != 'root'), isEmpty);
  });
}
