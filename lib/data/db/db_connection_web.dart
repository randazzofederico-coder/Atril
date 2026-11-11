import 'package:drift/drift.dart';

// Implementación web: se completa en la etapa 1.2 (drift sobre WASM).

QueryExecutor openMainDatabase() =>
    throw UnsupportedError('Base de datos web todavía no implementada');

QueryExecutor openDatabaseAtPath(String path) =>
    throw UnsupportedError('Base de datos web todavía no implementada');

Future<String> mainDatabasePath() =>
    throw UnsupportedError('En web la base no vive en un archivo de AtrilFs');

Future<void> snapshotDatabaseTo(GeneratedDatabase db, String path) =>
    throw UnsupportedError('Base de datos web todavía no implementada');
