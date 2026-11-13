import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'atril_fs.dart';

AtrilFs createPlatformFs() => WebAtrilFs();

/// Implementación web (PWA) sobre IndexedDB.
///
/// Se eligió IndexedDB (y no OPFS) porque está disponible y es estable en
/// todos los navegadores, incluido Safari en iOS, desde el hilo principal.
///
/// Dos object stores, con la ruta normalizada como clave:
/// - `meta`: datos chicos de cada entrada `{s: tamaño, m: ms, dir: bool}`.
///   Listar, "¿existe?", tamaño y fecha usan SOLO este store: nunca leen
///   el contenido (antes se leía el PDF entero para saber si era carpeta).
/// - `entries`: contenido de los archivos `{d: Uint8Array, m: ms}`.
///
/// Los archivos se leen de a uno (nunca se carga toda la biblioteca en memoria).
class WebAtrilFs extends AtrilFs {
  static const _dbName = 'atril_fs';
  static const _dbVersion = 2;
  static const _data = 'entries';
  static const _meta = 'meta';
  static const _docsRoot = '/documents';
  static const _tempRoot = '/tmp';

  Future<web.IDBDatabase>? _dbFuture;
  bool _persistRequested = false;
  final _random = Random();

  @override
  bool get isNative => false;

  @override
  String? get systemTempPath => null;

  @override
  Future<String> appDocumentsPath() async {
    _requestPersistence();
    await createDir(_docsRoot);
    return _docsRoot;
  }

  @override
  Future<String> tempPath() async {
    await createDir(_tempRoot);
    return _tempRoot;
  }

  @override
  Future<String> createTempDir(String prefix) async {
    final suffix = '${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(1 << 20)}';
    final dir = p.url.join(await tempPath(), '$prefix$suffix');
    await createDir(dir);
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Consultas (solo `meta`)
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) async {
    final m = await _getMeta(_norm(path));
    return m != null && !_isDir(m);
  }

  @override
  Future<bool> dirExists(String path) async {
    final key = _norm(path);
    if (key == '/') return true;
    final m = await _getMeta(key);
    if (m != null) return _isDir(m);
    return (await _metaKeysUnder(key)).isNotEmpty;
  }

  @override
  Future<int> length(String path) async {
    final m = await _getMeta(_norm(path));
    if (m == null || _isDir(m)) throw StateError('No existe el archivo: $path');
    return m.getProperty<JSNumber?>('s'.toJS)?.toDartInt ?? 0;
  }

  @override
  Future<DateTime?> modified(String path) async {
    final m = await _getMeta(_norm(path));
    final ms = m?.getProperty<JSNumber?>('m'.toJS);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms.toDartInt);
  }

  @override
  Future<List<FsEntry>> list(String dir, {bool recursive = false}) async {
    final base = _norm(dir);
    final prefix = base == '/' ? '/' : '$base/';
    final (keys, values) = await _metaUnder(base);
    final out = <String, bool>{}; // ruta -> esDirectorio
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final parts = k.substring(prefix.length).split('/');
      // Directorios intermedios (por si faltara su entrada)
      final maxDepth = recursive ? parts.length - 1 : min(1, parts.length - 1);
      for (var d = 1; d <= maxDepth; d++) {
        out['$prefix${parts.take(d).join('/')}'] = true;
      }
      if (recursive || parts.length == 1) {
        out[k] = (out[k] ?? false) || _isDir(values[i]);
      }
    }
    return [for (final e in out.entries) FsEntry(e.key, isDirectory: e.value)];
  }

  // ---------------------------------------------------------------------------
  // Lectura / escritura
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List> readBytes(String path) async {
    final db = await _db();
    final store = db.transaction(_data.toJS, 'readonly').objectStore(_data);
    final v = await _request(store.get(_norm(path).toJS));
    if (v == null || v.isUndefinedOrNull) throw StateError('No existe el archivo: $path');
    final d = (v as JSObject).getProperty<JSUint8Array?>('d'.toJS);
    if (d == null) throw StateError('No existe el archivo: $path');
    return d.toDart;
  }

  @override
  Future<String> readString(String path) async =>
      const Utf8Decoder().convert(await readBytes(path));

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final key = _norm(path);
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _write((dataStore, metaStore) {
      _putParents(metaStore, key, now);
      dataStore.put(_dataValue(data, now), key.toJS);
      metaStore.put(_metaValue(size: data.length, mtime: now), key.toJS);
    });
  }

  @override
  Future<void> writeString(String path, String contents) =>
      writeBytes(path, const Utf8Encoder().convert(contents));

  /// En IndexedDB una escritura ya es atómica (una transacción).
  @override
  Future<void> writeBytesAtomic(String path, List<int> bytes) => writeBytes(path, bytes);

  // ---------------------------------------------------------------------------
  // Manipulación
  // ---------------------------------------------------------------------------

  @override
  Future<void> createDir(String path) async {
    final key = _norm(path);
    if (key == '/') return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _write((_, metaStore) {
      _putParents(metaStore, key, now);
      metaStore.put(_metaValue(dir: true, mtime: now), key.toJS);
    });
  }

  @override
  Future<void> copy(String from, String to) async => writeBytes(to, await readBytes(from));

  @override
  Future<void> rename(String from, String to) async {
    final src = _norm(from);
    final dst = _norm(to);
    if (src == dst) return;

    final srcMeta = await _getMeta(src);
    final (childKeys, childMetas) = await _metaUnder(src);
    if (srcMeta == null && childKeys.isEmpty) throw StateError('No existe: $from');

    // Todo lo que se mueve: meta + contenido de los archivos (como objetos JS,
    // sin pasar los bytes por Dart).
    final metas = <String, JSObject>{
      if (srcMeta != null) src: srcMeta,
      for (var i = 0; i < childKeys.length; i++) childKeys[i]: childMetas[i],
    };
    final datas = <String, JSAny>{};
    final db = await _db();
    for (final e in metas.entries) {
      if (_isDir(e.value)) continue;
      final store = db.transaction(_data.toJS, 'readonly').objectStore(_data);
      final v = await _request(store.get(e.key.toJS));
      if (v != null && !v.isUndefinedOrNull) datas[e.key] = v;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _write((dataStore, metaStore) {
      // Sobrescribir el destino (como dart:io): borrar lo que hubiera
      for (final s in [dataStore, metaStore]) {
        s.delete(dst.toJS);
        s.delete(_range(dst));
      }
      _putParents(metaStore, dst, now);
      for (final e in metas.entries) {
        final newKey = (dst + e.key.substring(src.length)).toJS;
        metaStore.delete(e.key.toJS);
        metaStore.put(e.value, newKey);
        final v = datas[e.key];
        if (v != null) {
          dataStore.delete(e.key.toJS);
          dataStore.put(v, newKey);
        }
      }
      if (srcMeta == null) metaStore.put(_metaValue(dir: true, mtime: now), dst.toJS);
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    final key = _norm(path);
    final m = await _getMeta(key);
    if (m == null || _isDir(m)) return;
    await _write((dataStore, metaStore) {
      dataStore.delete(key.toJS);
      metaStore.delete(key.toJS);
    });
  }

  @override
  Future<void> deleteDir(String path) async {
    final key = _norm(path);
    if (key == '/') return;
    await _write((dataStore, metaStore) {
      for (final s in [dataStore, metaStore]) {
        s.delete(key.toJS);
        s.delete(_range(key));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // IndexedDB
  // ---------------------------------------------------------------------------

  /// Pide al navegador que no borre los datos ante falta de espacio
  /// (best-effort: en Safari solo tiene efecto con la PWA instalada).
  void _requestPersistence() {
    if (_persistRequested) return;
    _persistRequested = true;
    try {
      web.window.navigator.storage.persist().toDart.then(
            (granted) => granted.toDart,
            onError: (_) => false,
          );
    } catch (_) {}
  }

  Future<web.IDBDatabase> _db() => _dbFuture ??= _open();

  Future<web.IDBDatabase> _open() {
    final completer = Completer<web.IDBDatabase>();
    final req = web.window.indexedDB.open(_dbName, _dbVersion);
    req.onupgradeneeded = ((web.IDBVersionChangeEvent e) {
      final db = req.result as web.IDBDatabase;
      final tx = req.transaction!;
      if (!db.objectStoreNames.contains(_data)) db.createObjectStore(_data);
      if (!db.objectStoreNames.contains(_meta)) {
        db.createObjectStore(_meta);
        if (e.oldVersion >= 1) _migrateV1(tx);
      }
    }).toJS;
    req.onsuccess = ((web.Event _) {
      completer.complete(req.result as web.IDBDatabase);
    }).toJS;
    req.onerror = ((web.Event _) {
      _dbFuture = null;
      completer.completeError(
        StateError('No se pudo abrir el almacenamiento del navegador: ${req.error?.message}'),
      );
    }).toJS;
    req.onblocked = ((web.Event _) {
      // Otra pestaña con una versión vieja abierta: se resolverá al cerrarla.
    }).toJS;
    return completer.future;
  }

  /// v1 → v2: arma `meta` recorriendo `entries` una sola vez (dentro de la
  /// transacción de actualización) y saca de `entries` las marcas de carpeta.
  static void _migrateV1(web.IDBTransaction tx) {
    final dataStore = tx.objectStore(_data);
    final metaStore = tx.objectStore(_meta);
    final cursorReq = dataStore.openCursor();
    cursorReq.onsuccess = ((web.Event _) {
      final cursor = cursorReq.result as web.IDBCursorWithValue?;
      if (cursor == null) return;
      final v = cursor.value as JSObject;
      final m = v.getProperty<JSNumber?>('m'.toJS)?.toDartInt ?? 0;
      if (_isDir(v)) {
        metaStore.put(_metaValue(dir: true, mtime: m), cursor.key);
        cursor.delete();
      } else {
        final d = v.getProperty<JSUint8Array?>('d'.toJS);
        final size = d?.getProperty<JSNumber>('length'.toJS).toDartInt ?? 0;
        metaStore.put(_metaValue(size: size, mtime: m), cursor.key);
      }
      cursor.continue_();
    }).toJS;
  }

  Future<JSAny?> _request(web.IDBRequest req) {
    final completer = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => completer.complete(req.result)).toJS;
    req.onerror = ((web.Event _) => completer.completeError(
          StateError('Error de almacenamiento: ${req.error?.message}'),
        )).toJS;
    return completer.future;
  }

  Future<JSObject?> _getMeta(String key) async {
    final db = await _db();
    final store = db.transaction(_meta.toJS, 'readonly').objectStore(_meta);
    final result = await _request(store.get(key.toJS));
    if (result == null || result.isUndefinedOrNull) return null;
    return result as JSObject;
  }

  Future<List<String>> _metaKeysUnder(String dir) async => (await _metaUnder(dir)).$1;

  /// Claves y metadatos de todo lo que está debajo de [dir] (sin [dir]).
  Future<(List<String>, List<JSObject>)> _metaUnder(String dir) async {
    final db = await _db();
    final tx = db.transaction(_meta.toJS, 'readonly');
    final store = tx.objectStore(_meta);
    final keysF = _request(store.getAllKeys(_range(dir)));
    final valuesF = _request(store.getAll(_range(dir)));
    final keys = ((await keysF) as JSArray<JSAny?>).toDart;
    final values = ((await valuesF) as JSArray<JSAny?>).toDart;
    return (
      [for (final k in keys) (k as JSString).toDart],
      [for (final v in values) v as JSObject],
    );
  }

  /// Ejecuta escrituras en UNA transacción sobre ambos stores (todas las
  /// requests se emiten de forma sincrónica dentro de [body]) y espera a que
  /// se confirme.
  Future<void> _write(void Function(web.IDBObjectStore data, web.IDBObjectStore meta) body) async {
    final db = await _db();
    final tx = db.transaction([_data.toJS, _meta.toJS].toJS, 'readwrite');
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Error de almacenamiento: ${tx.error?.message}'));
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        final msg = tx.error?.message ?? 'transacción abortada';
        completer.completeError(
          msg.contains('Quota') ? StateError('No hay espacio suficiente en el navegador.') : StateError(msg),
        );
      }
    }).toJS;
    body(tx.objectStore(_data), tx.objectStore(_meta));
    return completer.future;
  }

  /// Marca como carpetas los padres de [key].
  static void _putParents(web.IDBObjectStore metaStore, String key, int now) {
    var parent = p.url.dirname(key);
    while (parent != '/' && parent != '.' && parent.isNotEmpty) {
      metaStore.put(_metaValue(dir: true, mtime: now), parent.toJS);
      parent = p.url.dirname(parent);
    }
  }

  /// Rango de claves estrictamente debajo de [dir].
  static web.IDBKeyRange _range(String dir) {
    final prefix = dir == '/' ? '/' : '$dir/';
    return web.IDBKeyRange.bound(prefix.toJS, '$prefix\uffff'.toJS);
  }

  static JSObject _dataValue(Uint8List data, int mtime) {
    final o = JSObject();
    o.setProperty('d'.toJS, data.toJS);
    o.setProperty('m'.toJS, mtime.toJS);
    return o;
  }

  static JSObject _metaValue({int size = 0, required int mtime, bool dir = false}) {
    final o = JSObject();
    o.setProperty('s'.toJS, size.toJS);
    o.setProperty('m'.toJS, mtime.toJS);
    if (dir) o.setProperty('dir'.toJS, true.toJS);
    return o;
  }

  static bool _isDir(JSObject e) => e.getProperty<JSBoolean?>('dir'.toJS)?.toDart ?? false;

  /// Normaliza a ruta absoluta estilo URL sin `/` final.
  static String _norm(String path) {
    var n = p.url.normalize(path.replaceAll('\\', '/'));
    if (!n.startsWith('/')) n = '/$n';
    if (n.length > 1 && n.endsWith('/')) n = n.substring(0, n.length - 1);
    return n;
  }
}
