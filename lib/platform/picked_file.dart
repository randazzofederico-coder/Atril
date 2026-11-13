import 'dart:typed_data';

/// Archivo elegido en el navegador, todavía sin leer.
class PickedFile {
  final String name;
  final int size;
  final Future<Uint8List> Function(void Function(int read)? onBytes) _read;

  PickedFile(this.name, this.size, this._read);

  /// Lee el contenido; [onBytes] recibe los bytes leídos hasta el momento.
  Future<Uint8List> read({void Function(int read)? onBytes}) => _read(onBytes);
}
