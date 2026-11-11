import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db_connection.dart';

QueryExecutor openMainDatabase() {
  return LazyDatabase(() async {
    // La DB vive en la carpeta de Documentos para que coincida con donde la
    // busca el BackupManager.
    return NativeDatabase.createInBackground(File(await mainDatabasePath()));
  });
}

QueryExecutor openDatabaseAtPath(String path) => NativeDatabase(File(path));

Future<String> mainDatabasePath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return p.join(dbFolder.path, kMainDbFileName);
}

Future<void> snapshotDatabaseTo(GeneratedDatabase db, String path) async {
  await Directory(p.dirname(path)).create(recursive: true);
  await db.customStatement('VACUUM INTO ?', [path]);
}
