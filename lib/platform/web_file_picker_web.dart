import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Completer<List<web.File>>? _pending;

/// Abandona la selección en curso (el usuario tocó "Cancelar" mientras
/// esperaba a Drive). Si el archivo llega después, se ignora.
void cancelPendingPick() {
  final c = _pending;
  if (c != null && !c.isCompleted) c.complete(const []);
}

/// Selector de archivos del navegador, sin la detección de "cancelado" por
/// foco de file_picker (en Android, al volver de Drive mientras descarga,
/// la tomaba como cancelación y la importación quedaba colgada).
///
/// Chrome descarga los archivos de Drive ANTES de entregarlos a la página y
/// no informa el avance. Por eso:
/// - [onWaiting]: el usuario volvió del selector pero los archivos todavía no
///   llegaron (casi siempre: Drive descargando).
/// - [onChosen]: llegaron los archivos; empieza la lectura.
/// - [onRead]: se leyó el archivo i de n.
///
/// [accept]: extensiones y/o tipos MIME (p. ej. `.pdf,application/pdf`).
/// Devuelve lista vacía si canceló.
Future<List<(String, Uint8List)>> pickFilesWeb({
  required String accept,
  bool multiple = false,
  void Function()? onWaiting,
  void Function(int count)? onChosen,
  void Function(int done, int total)? onRead,
}) {
  cancelPendingPick();
  final completer = _pending = Completer<List<web.File>>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple
    ..style.display = 'none';

  JSFunction? focusListener;
  void finish(List<web.File> files) {
    if (!completer.isCompleted) completer.complete(files);
    input.remove();
    if (focusListener != null) web.window.removeEventListener('focus', focusListener);
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

  // Volvió del selector y todavía no hay archivos: está bajando (o el
  // navegador no avisa la cancelación). Se avisa con un pequeño margen para
  // no parpadear cuando el archivo es local y llega enseguida.
  focusListener = ((web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!completer.isCompleted) onWaiting?.call();
    });
  }).toJS;
  web.window.addEventListener('focus', focusListener);

  web.document.body?.append(input);
  input.click();

  return completer.future.then((files) async {
    if (files.isEmpty) return const <(String, Uint8List)>[];
    onChosen?.call(files.length);
    final out = <(String, Uint8List)>[];
    for (var i = 0; i < files.length; i++) {
      final buffer = await files[i].arrayBuffer().toDart;
      out.add((files[i].name, buffer.toDart.asUint8List()));
      onRead?.call(i + 1, files.length);
    }
    return out;
  });
}
