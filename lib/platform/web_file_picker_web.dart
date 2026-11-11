import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Selector de archivos del navegador, sin la detección de "cancelado" por
/// foco de file_picker (en Android, al volver de Drive mientras descarga,
/// la tomaba como cancelación y la importación quedaba colgada).
///
/// [accept]: extensiones y/o tipos MIME (p. ej. `.pdf,application/pdf`).
/// [onChosen] se llama apenas el usuario confirmó (antes de leer los bytes),
/// para mostrar "Descargando..." recién entonces.
/// Devuelve lista vacía si canceló.
Future<List<(String, Uint8List)>> pickFilesWeb({
  required String accept,
  bool multiple = false,
  void Function()? onChosen,
}) {
  final completer = Completer<List<web.File>>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple
    ..style.display = 'none';

  void finish(List<web.File> files) {
    if (!completer.isCompleted) completer.complete(files);
    input.remove();
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final list = input.files;
      final files = <web.File>[];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          final f = list.item(i);
          if (f != null) files.add(f);
        }
      }
      finish(files);
    }).toJS,
  );
  // Evento estándar de cancelación (Chrome 113+, Safari 16.4+, Firefox 91+).
  input.addEventListener('cancel', ((web.Event _) => finish(const [])).toJS);

  web.document.body?.append(input);
  input.click();

  return completer.future.then((files) async {
    if (files.isEmpty) return const <(String, Uint8List)>[];
    onChosen?.call();
    final out = <(String, Uint8List)>[];
    for (final f in files) {
      final buffer = await f.arrayBuffer().toDart;
      out.add((f.name, buffer.toDart.asUint8List()));
    }
    return out;
  });
}
