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
/// Modelo: un object store `entries` cuya clave es la ruta normalizada.
/// - Archivo: `{d: Uint8Array, m: <ms>}`
/// - Directorio: `{dir: true, m: <ms>}` (los padres se crean solos al escribir)
///
/// Los archivos se leen de a uno (nunca se carga toda la biblioteca en memoria).
class WebAtrilFs extends AtrilFs {
  static const _dbName = 'atril_fs';
  static const _store = 'entries';
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
  // Consultas
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) async {
    final e = await _get(_norm(path));
    return e != null && !_isDir(e);
  }

  @override
  Future<bool> dirExists(String path) async {
    final key = _norm(path);
    if (key == '/') return true;
    final e = await _get(key);
    if (e != null) return _isDir(e);
    // Directorio implícito (tiene contenido aunque no tenga marcador)
    return (await _keysUnder(key)).isNotEmpty;
  }

  @override
  Future<int> length(String path) async => (await readBytes(path)).length;

  @override
  Future<DateTime?> modified(String path) async {
    final e = await _get(_norm(path));
    if (e == null) return null;
    final m = e.getProperty<JSNumber?>('m'.toJS);
    return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m.toDartInt);
  }

  @override
  Future<List<FsEntry>> list(String dir, {bool recursive = false}) async {
    final base = _norm(dir);
    final keys = await _keysUnder(base);
    final prefix = base == '/' ? '/' : '$base/';
    final out = <String, bool>{}; // ruta -> esDirectorio

    for (final k in keys) {
      final rest = k.substring(prefix.length);
      final parts = rest.split('/');
      // Directorios intermedios (implícitos o con marcador)
      final maxDepth = recursive ? parts.length - 1 : min(1, parts.length - 1);
      for (var i = 1; i <= maxDepth; i++) {
        out['$prefix${parts.take(i).join('/')}'] = true;
      }
      if (recursive || parts.length == 1) {
        out.putIfAbsent(k, () => false);
      }
    }

    // Distinguir marcadores de directorio de archivos
    final candidates = out.entries.where((e) => !e.value).map((e) => e.key).toList();
    if (candidates.isNotEmpty) {
      final dirs = await _dirMarkers(candidates);
      for (final d in dirs) {
        out[d] = true;
      }
    }

    return [for (final e in out.entries) FsEntry(e.key, isDirectory: e.value)];
  }

  // ---------------------------------------------------------------------------
  // Lectura / escritura
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List> readBytes(String path) async {
    final e = await _get(_norm(path));
    if (e == null || _isDir(e)) {
      throw StateError('No existe el archivo: $path');
    }
    return e.getProperty<JSUint8Array>('d'.toJS).toDart;
  }

  @override
  Future<String> readString(String path) async {
    return const Utf8Decoder().convert(await readBytes(path));
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final key = _norm(path);
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await _write((store) {
      _putParents(store, key);
      store.put(_fileValue(data), key.toJS);
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
    await _write((store) {
      _putParents(store, key);
      store.put(_dirValue(), key.toJS);
    });
  }

  @override
  Future<void> copy(String from, String to) async {
    final data = await readBytes(from);
    await writeBytes(to, data);
  }

  @override
  Future<void> rename(String from, String to) async {
    final src = _norm(from);
    final dst = _norm(to);
    if (src == dst) return;

    final entry = await _get(src);
    final children = await _keysUnder(src);
    if (entry == null && children.isEmpty) {
      throw StateError('No existe: $from');
    }

    // Leer todo lo que se mueve (fuera de la transacción de escritura)
    final moved = <String, JSObject>{};
    if (entry != null) moved[src] = entry;
    for (final k in children) {
      final v = await _get(k);
      if (v != null) moved[k] = v;
    }

    await _write((store) {
      // Sobrescribir el destino (como dart:io): borrar lo que hubiera
      store.delete(dst.toJS);
      store.delete(_range(dst));
      _putParents(store, dst);
      for (final e in moved.entries) {
        store.delete(e.key.toJS);
        store.put(e.value, (dst + e.key.substring(src.length)).toJS);
      }
      if (entry == null) store.put(_dirValue(), dst.toJS);
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    final key = _norm(path);
    final e = await _get(key);
    if (e == null || _isDir(e)) return;
    await _write((store) => store.delete(key.toJS));
  }

  @override
  Future<void> deleteDir(String path) async {
    final key = _norm(path);
    if (key == '/') return;
    await _write((store) {
      store.delete(key.toJS);
      store.delete(_range(key));
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
    final req = web.window.indexedDB.open(_dbName, 1);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) {
        db.createObjectStore(_store);
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

  Future<JSAny?> _request(web.IDBRequest req) {
    final completer = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => completer.complete(req.result)).toJS;
    req.onerror = ((web.Event _) => completer.completeError(
          StateError('Error de almacenamiento: ${req.error?.message}'),
        )).toJS;
    return completer.future;
  }

  Future<JSObject?> _get(String key) async {
    final db = await _db();
    final store = db.transaction(_store.toJS, 'readonly').objectStore(_store);
    final result = await _request(store.get(key.toJS));
    if (result == null || result.isUndefinedOrNull) return null;
    return result as JSObject;
  }

  /// Todas las claves debajo de [dir] (sin incluir [dir]).
  Future<List<String>> _keysUnder(String dir) async {
    final db = await _db();
    final store = db.transaction(_store.toJS, 'readonly').objectStore(_store);
    final result = await _request(store.getAllKeys(_range(dir)));
    final arr = (result as JSArray<JSAny?>).toDart;
    return [for (final k in arr) (k as JSString).toDart];
  }

  /// De [keys], cuáles son marcadores de directorio.
  Future<Set<String>> _dirMarkers(List<String> keys) async {
    final out = <String>{};
    for (final k in keys) {
      final e = await _get(k);
      if (e != null && _isDir(e)) out.add(k);
    }
    return out;
  }

  /// Ejecuta escrituras en UNA transacción (todas las requests se emiten de
  /// forma sincrónica dentro de [body]) y espera a que se confirme.
  Future<void> _write(void Function(web.IDBObjectStore store) body) async {
    final db = await _db();
    final tx = db.transaction(_store.toJS, 'readwrite');
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) => completer.completeError(
          StateError('Error de almacenamiento: ${tx.error?.message}'),
        )).toJS;
    tx.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        final msg = tx.error?.message ?? 'transacción abortada';
        completer.completeError(
          msg.contains('Quota') ? StateError('No hay espacio suficiente en el navegador.') : StateError(msg),
        );
      }
    }).toJS;
    body(tx.objectStore(_store));
    return completer.future;
  }

  /// Crea marcadores para los directorios padre de [key].
  void _putParents(web.IDBObjectStore store, String key) {
    var parent = p.url.dirname(key);
    while (parent != '/' && parent != '.' && parent.isNotEmpty) {
      store.put(_dirValue(), parent.toJS);
      parent = p.url.dirname(parent);
    }
  }

  /// Rango de claves estrictamente debajo de [dir].
  web.IDBKeyRange _range(String dir) {
    final prefix = dir == '/' ? '/' : '$dir/';
    return web.IDBKeyRange.bound(prefix.toJS, '$prefix\uffff'.toJS);
  }

  static JSObject _fileValue(Uint8List data) {
    final o = JSObject();
    o.setProperty('d'.toJS, data.toJS);
    o.setProperty('m'.toJS, DateTime.now().millisecondsSinceEpoch.toJS);
    return o;
  }

  static JSObject _dirValue() {
    final o = JSObject();
    o.setProperty('dir'.toJS, true.toJS);
    o.setProperty('m'.toJS, DateTime.now().millisecondsSinceEpoch.toJS);
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
