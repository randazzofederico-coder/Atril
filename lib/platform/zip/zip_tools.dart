import 'zip_tools_io.dart' if (dart.library.js_interop) 'zip_tools_web.dart' as impl;

/// Una entrada a comprimir: un archivo de [AtrilFs] ([sourcePath]) o bytes en
/// memoria ([bytes]), guardados dentro del ZIP como [zipPath].
class ZipEntrySpec {
  final String zipPath;
  final String? sourcePath;
  final List<int>? bytes;

  const ZipEntrySpec.file(String this.sourcePath, this.zipPath) : bytes = null;
  const ZipEntrySpec.bytes(List<int> this.bytes, this.zipPath) : sourcePath = null;
}

/// Compresión / descompresión de ZIP sobre rutas de [AtrilFs].
///
/// - Nativo: en un Isolate, por streams (no carga el ZIP entero en memoria).
/// - Web: en memoria, en el mismo hilo.
///
/// Las entradas cuyo archivo de origen no existe se omiten. Las entradas de un
/// ZIP que intenten escribir fuera de [destDir] (zip-slip) se ignoran.
/// Ambas funciones lanzan una excepción si fallan.
class ZipTools {
  ZipTools._();

  static Future<void> zipToFile(
    String outputPath,
    List<ZipEntrySpec> entries, {
    void Function(double progress)? onProgress,
  }) =>
      impl.zipToFile(outputPath, entries, onProgress: onProgress);

  static Future<void> unzipToDir(
    String zipPath,
    String destDir, {
    void Function(double progress)? onProgress,
  }) =>
      impl.unzipToDir(zipPath, destDir, onProgress: onProgress);

  /// Nombres de las entradas del ZIP, o null si el archivo no existe o no es
  /// un ZIP (no tiene la cabecera `PK`).
  static Future<List<String>?> listEntryNames(String zipPath) =>
      impl.listEntryNames(zipPath);
}
