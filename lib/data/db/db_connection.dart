import 'package:drift/drift.dart';

import 'db_connection_io.dart' if (dart.library.js_interop) 'db_connection_web.dart' as impl;

/// Nombre del archivo SQLite principal (también es el nombre dentro de un
/// backup `.atril`).
const String kMainDbFileName = 'atril.sqlite';

/// Conexión a la base principal de la app.
/// - Nativo: `<documentos>/atril.sqlite` (drift `NativeDatabase`).
/// - Web: SQLite compilado a WASM sobre el almacenamiento del navegador.
QueryExecutor openMainDatabase() => impl.openMainDatabase();

/// Abre un archivo SQLite de [AtrilFs] (p. ej. la base de un backup extraído).
QueryExecutor openDatabaseAtPath(String path) => impl.openDatabaseAtPath(path);

/// Ruta de [AtrilFs] del archivo de la base principal (solo nativo: en web la
/// base no vive en un archivo de AtrilFs).
Future<String> mainDatabasePath() => impl.mainDatabasePath();

/// Escribe en [path] (de [AtrilFs]) una copia consistente de [db], aunque la
/// app esté escribiendo (nativo: `VACUUM INTO`).
Future<void> snapshotDatabaseTo(GeneratedDatabase db, String path) =>
    impl.snapshotDatabaseTo(db, path);
