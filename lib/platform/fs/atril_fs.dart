import 'dart:typed_data';

import 'atril_fs_io.dart' if (dart.library.js_interop) 'atril_fs_web.dart' as impl;

/// Sistema de archivos de Atril, independiente de la plataforma.
///
/// Todo el código de datos trabaja con **rutas de texto** (igual que antes con
/// `dart:io`), pero a través de esta interfaz:
/// - Android/escritorio: delega en `dart:io` ([impl] = `atril_fs_io.dart`).
/// - Web/PWA: rutas virtuales sobre el Origin Private File System (OPFS).
///
/// Así la lógica (importar, editar, exportar, backup) es la misma en todas las
/// plataformas y solo cambia esta capa.
///
/// Convenciones:
/// - Las operaciones de borrado no fallan si la ruta no existe.
/// - Las escrituras crean los directorios padre que falten.
abstract class AtrilFs {
  /// Instancia global. Reemplazable en tests.
  static AtrilFs instance = impl.createPlatformFs();

  /// `true` si las rutas son reales del sistema operativo (se pueden pasar a
  /// APIs nativas que esperan un path, p. ej. compartir o abrir con pdfrx).
  bool get isNative;

  /// Directorio de documentos de la app (persistente).
  Future<String> appDocumentsPath();

  /// Directorio temporal de la app (el sistema o la app pueden limpiarlo).
  Future<String> tempPath();

  /// Temporal del sistema operativo, si es distinto del de la app (solo nativo).
  String? get systemTempPath;

  /// Crea un directorio temporal nuevo y único con el [prefix] dado.
  Future<String> createTempDir(String prefix);

  // --- Consultas ---

  Future<bool> fileExists(String path);
  Future<bool> dirExists(String path);

  /// Tamaño en bytes del archivo.
  Future<int> length(String path);

  /// Última modificación del archivo o directorio (null si no se sabe).
  Future<DateTime?> modified(String path);

  /// Lista el contenido de [dir]. Si no existe, devuelve una lista vacía.
  Future<List<FsEntry>> list(String dir, {bool recursive = false});

  // --- Lectura / escritura ---

  Future<Uint8List> readBytes(String path);
  Future<String> readString(String path);

  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> writeString(String path, String contents);

  /// Escribe en `path.tmp` y renombra: un corte a mitad nunca deja un archivo
  /// a medio escribir en [path].
  Future<void> writeBytesAtomic(String path, List<int> bytes) async {
    final tmp = '$path.tmp';
    await writeBytes(tmp, bytes);
    await rename(tmp, path);
  }

  // --- Manipulación ---

  Future<void> createDir(String path);

  /// Copia un archivo (sobrescribe el destino).
  Future<void> copy(String from, String to);

  /// Mueve/renombra un archivo o directorio (sobrescribe un archivo destino).
  Future<void> rename(String from, String to);

  /// Borra un archivo.
  Future<void> deleteFile(String path);

  /// Borra un directorio y todo su contenido.
  Future<void> deleteDir(String path);
}

/// Entrada de un listado de directorio.
class FsEntry {
  final String path;
  final bool isDirectory;
  const FsEntry(this.path, {required this.isDirectory});

  bool get isFile => !isDirectory;

  @override
  String toString() => 'FsEntry($path${isDirectory ? '/' : ''})';
}

/// Atajo: `fs.readBytes(...)`.
AtrilFs get fs => AtrilFs.instance;
