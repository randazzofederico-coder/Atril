import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

import '../../platform/fs/atril_fs.dart';

// Web: SQLite compilado a WASM (`web/sqlite3.wasm`) en el hilo principal,
// persistido en IndexedDB con el VFS de package:sqlite3.
//
// No se usa el worker de drift a propósito: con la base en este mismo
// contexto podemos leer y reemplazar sus bytes para los backups (.atril).
// Contrapartida: no hay que abrir Atril en dos pestañas a la vez.

const _wasmUri = 'sqlite3.wasm';
const _vfsName = 'atril-idb';
const _idbName = 'atril_db';
const _dbPath = '/atril.sqlite';

WasmSqlite3? _sqlite3;
IndexedDbFileSystem? _vfs;

Future<(WasmSqlite3, IndexedDbFileSystem)> _mainEnv() async {
  final sqlite3 = _sqlite3 ??= await WasmSqlite3.loadFromUrl(Uri.parse(_wasmUri));
  var vfs = _vfs;
  if (vfs == null || vfs.isClosed) {
    vfs = _vfs = await IndexedDbFileSystem.open(dbName: _idbName, vfsName: _vfsName);
    sqlite3.registerVirtualFileSystem(vfs, makeDefault: true);
  }
  return (sqlite3, vfs);
}

QueryExecutor openMainDatabase() {
  return LazyDatabase(() async {
    final (sqlite3, vfs) = await _mainEnv();
    return WasmDatabase(sqlite3: sqlite3, path: _dbPath, fileSystem: vfs);
  });
}

var _importCounter = 0;

/// Abre un archivo SQLite de [AtrilFs] (p. ej. el de un backup) en memoria,
/// en una instancia de SQLite aparte (no toca la base principal).
QueryExecutor openDatabaseAtPath(String path) {
  return LazyDatabase(() async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse(_wasmUri));
    final memory = InMemoryFileSystem(name: 'atril-import-${_importCounter++}');
    sqlite3.registerVirtualFileSystem(memory, makeDefault: true);
    _writeFile(memory, '/import.sqlite', await fs.readBytes(path));
    return WasmDatabase(sqlite3: sqlite3, path: '/import.sqlite');
  });
}

Future<String> mainDatabasePath() =>
    throw UnsupportedError('En web la base no vive en un archivo de AtrilFs');

/// Copia los bytes de la base principal a [path]. Se hace dentro de una
/// transacción para que ninguna escritura quede a medias en la copia.
Future<void> snapshotDatabaseTo(GeneratedDatabase db, String path) async {
  late Uint8List bytes;
  await db.transaction(() async {
    final (_, vfs) = await _mainEnv();
    bytes = _readFile(vfs, _dbPath);
  });
  await fs.writeBytes(path, bytes);
}

Uint8List _readFile(VirtualFileSystem vfs, String path) {
  final file = vfs.xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY).file;
  try {
    final out = Uint8List(file.xFileSize());
    file.xRead(out, 0);
    return out;
  } finally {
    file.xClose();
  }
}

void _writeFile(VirtualFileSystem vfs, String path, Uint8List bytes) {
  final file = vfs
      .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
      .file;
  try {
    file.xTruncate(0);
    file.xWrite(bytes, 0);
  } finally {
    file.xClose();
  }
}
