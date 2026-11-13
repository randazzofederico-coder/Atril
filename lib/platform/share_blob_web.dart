import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'diag_log.dart';
import 'root_messenger.dart';
import 'web_blobs.dart';

/// Si [path] es un resultado guardado como Blob (ver [webBlobs]), lo comparte.
///
/// El navegador solo abre el menú de compartir si el usuario tocó algo hace
/// instantes. Por eso:
/// - Si ese toque todavía vale (proceso corto): menú de compartir directo.
/// - Si no (proceso largo): aviso "Listo" con botón Compartir (el toque del
///   usuario habilita el menú). Si lo ignora, se descarga solo.
/// Devuelve false si no hay Blob para esa ruta.
Future<bool> shareRegisteredBlob(String path, {String? mimeType, String? subject, String? text}) async {
  final blob = webBlobs.remove(path);
  if (blob == null) return false;
  final name = p.basename(path);
  final file = web.File(
    [blob].toJS,
    name,
    web.FilePropertyBag(type: mimeType ?? (blob.type.isEmpty ? 'application/octet-stream' : blob.type)),
  );
  final data = web.ShareData(files: [file].toJS, title: subject ?? name);
  if (text != null) data.text = text;

  final nav = web.window.navigator;
  var canShare = false;
  try {
    canShare = nav.canShare(data);
  } catch (_) {}
  if (!canShare) {
    _download(file, name);
    return true;
  }

  final sizeMb = (blob.size / 1048576).toStringAsFixed(1);
  final active = _userActivationActive();
  diag('share: $name ($sizeMb MB), toque vigente: ${active ?? 'desconocido'}');
  if (active != false) {
    final result = await _share(data);
    if (result != _ShareResult.notAllowed) {
      if (result == _ShareResult.failed) _download(file, name);
      return true;
    }
  }
  _offerShare(file, data, name, sizeMb);
  return true;
}

enum _ShareResult { done, notAllowed, failed }

Future<_ShareResult> _share(web.ShareData data) async {
  try {
    await web.window.navigator.share(data).toDart;
    return _ShareResult.done;
  } catch (e) {
    final s = '$e';
    if (s.contains('AbortError')) return _ShareResult.done; // el usuario cerró el menú
    if (s.contains('NotAllowedError')) return _ShareResult.notAllowed;
    diag('share: falló ($s)');
    return _ShareResult.failed;
  }
}

/// `navigator.userActivation.isActive`, o null si el navegador no lo informa.
bool? _userActivationActive() {
  try {
    final ua = web.window.navigator.getProperty<JSObject?>('userActivation'.toJS);
    if (ua == null) return null;
    return ua.getProperty<JSBoolean?>('isActive'.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

/// Aviso con botón "Compartir"; si se cierra sin tocarlo, se descarga.
void _offerShare(web.File file, web.ShareData data, String name, String sizeMb) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) {
    _download(file, name);
    return;
  }
  var handled = false;
  final controller = messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 30),
    content: Text('Listo: $name ($sizeMb MB)'),
    action: SnackBarAction(
      label: 'Compartir',
      onPressed: () async {
        handled = true;
        final r = await _share(data);
        if (r != _ShareResult.done) _download(file, name);
      },
    ),
  ));
  controller.closed.then((_) {
    if (!handled) _download(file, name);
  });
}

void _download(web.Blob blob, String name) {
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Dar tiempo a que empiece la descarga antes de liberar el Blob.
  Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  diag('share: descarga iniciada de $name');
}
