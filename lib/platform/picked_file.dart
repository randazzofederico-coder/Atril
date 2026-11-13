import 'dart:typed_data';

/// Archivo elegido en el navegador, todavía sin leer.
class PickedFile {
  final String name;
  final int size;
  final Future<Uint8List> Function(void Function(int read)? onBytes) _read;

  /// Objeto nativo del navegador (`File`), para leerlo por partes sin
  /// cargarlo entero (ZIP grandes). Opaco fuera de web.
  final Object? handle;

  PickedFile(this.name, this.size, this._read, {this.handle});

  /// Lee el contenido; [onBytes] recibe los bytes leídos hasta el momento.
  Future<Uint8List> read({void Function(int read)? onBytes}) => _read(onBytes);
}
