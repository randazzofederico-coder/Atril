import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_data.dart';
import 'package:pdf_setlist/data/app_database.dart';
import 'package:pdf_setlist/data/backup_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Restaurar Backup (Destructivo)": reemplaza la biblioteca, pero si el
/// backup es inválido o algo falla, la biblioteca actual queda intacta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;

  setUp(() async {
    appDir = await Directory.systemTemp.createTemp('restore_test_');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // path_provider: documentos y temporales apuntan al directorio del test
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => appDir.path,
    );
    // wakelock (lo toca AppData.init → settings)
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (msg) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    SharedPreferences.setMockInitialValues({});

    AppData.storage.initForTesting(Directory('${appDir.path}/atril'));
    AppData.db = AppDatabase(executor: NativeDatabase(File('${appDir.path}/atril.sqlite')));

    // Biblioteca actual: un doc "Actual" con su PDF
    await AppData.db.upsertDoc(id: 'actual', displayName: 'Actual', author: '',
        internalRelPath: 'docs/actual.pdf', folderId: 'root');
    File('${appDir.path}/atril/docs/actual.pdf').writeAsStringSync('%PDF actual');
  });

  tearDown(() async {
    await AppData.db.close();
    try { await appDir.delete(recursive: true); } catch (_) {}
  });

  Future<String> zipWith(Map<String, File> entries) async {
    final path = '${appDir.path}/in_${DateTime.now().microsecondsSinceEpoch}.atril';
    final enc = ZipFileEncoder()..create(path);
    for (final e in entries.entries) {
      await enc.addFile(e.value, e.key);
    }
    enc.close();
    return path;
  }

  Future<String> validBackup() async {
    final src = Directory('${appDir.path}/src')..createSync();
    final dbFile = File('${src.path}/atril.sqlite');
    final db = AppDatabase(executor: NativeDatabase(dbFile));
    await db.upsertDoc(id: 'nuevo', displayName: 'Nuevo', author: '',
        internalRelPath: 'docs/nuevo.pdf', folderId: 'root');
    await db.close();
    final pdf = File('${src.path}/nuevo.pdf')..writeAsStringSync('%PDF nuevo');
    return zipWith({'atril.sqlite': dbFile, 'docs/nuevo.pdf': pdf});
  }

  test('restaura un backup válido y la DB queda abierta', () async {
    final zip = await validBackup();

    await BackupManager.instance.restoreBackup(zip);

    final docs = await AppData.db.getAllDocs(); // DB reabierta y usable
    expect(docs.map((d) => d.id), ['nuevo']);
    expect(File('${appDir.path}/atril/docs/nuevo.pdf').existsSync(), isTrue);
    expect(File('${appDir.path}/atril/docs/actual.pdf').existsSync(), isFalse);
    // Sin resguardos sobrantes
    expect(File('${appDir.path}/atril.sqlite.restore_bak').existsSync(), isFalse);
    expect(Directory('${appDir.path}/atril/docs.restore_bak').existsSync(), isFalse);
  });

  test('un backup con base de datos dañada no toca la biblioteca actual', () async {
    final corrupt = File('${appDir.path}/corrupt.sqlite')..writeAsStringSync('esto no es sqlite');
    final zip = await zipWith({'atril.sqlite': corrupt});

    await expectLater(BackupManager.instance.restoreBackup(zip), throwsException);

    final docs = await AppData.db.getAllDocs();
    expect(docs.map((d) => d.id), ['actual']);
    expect(File('${appDir.path}/atril/docs/actual.pdf').existsSync(), isTrue);
  });

  test('un archivo sin base de datos no toca la biblioteca actual', () async {
    final junk = File('${appDir.path}/x.txt')..writeAsStringSync('hola');
    final zip = await zipWith({'x.txt': junk});

    await expectLater(BackupManager.instance.restoreBackup(zip), throwsException);
    expect((await AppData.db.getAllDocs()).map((d) => d.id), ['actual']);
  });
}
