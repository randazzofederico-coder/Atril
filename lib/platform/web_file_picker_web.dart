import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

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
/// no informa el avance. [onWaiting] avisa que el usuario volvió del selector
/// pero los archivos todavía no llegaron.
///
/// Devuelve los archivos sin leer: cada uno se lee con [PickedFile.read], que
/// informa los bytes leídos (lista vacía si canceló).
Future<List<PickedFile>> pickFilesWeb({
  required String accept,
  bool multiple = false,
  void Function()? onWaiting,
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

  // Volvió del selector y todavía no hay archivos: está bajando. Margen
  // corto para no parpadear cuando el archivo es local y llega enseguida.
  focusListener = ((web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!completer.isCompleted) onWaiting?.call();
    });
  }).toJS;
  web.window.addEventListener('focus', focusListener);

  web.document.body?.append(input);
  input.click();

  return completer.future.then((files) => [
        for (final f in files)
          PickedFile(f.name, f.size, (onBytes) => _readWithProgress(f, onBytes)),
      ]);
}

/// Lee el archivo por partes (stream) para poder informar el avance.
Future<Uint8List> _readWithProgress(web.File file, void Function(int read)? onBytes) async {
  final total = file.size;
  final out = Uint8List(total);
  var offset = 0;
  final reader = file.stream().getReader() as web.ReadableStreamDefaultReader;
  var lastReport = 0;
  while (true) {
    final result = await reader.read().toDart;
    if (result.done) break;
    final chunk = (result.value as JSUint8Array).toDart;
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
    // No saturar la UI: avisar cada ~2 MB
    if (offset - lastReport >= 2 * 1024 * 1024 || offset == total) {
      lastReport = offset;
      onBytes?.call(offset);
    }
  }
  return offset == total ? out : Uint8List.sublistView(out, 0, offset);
}
