import 'dart:js_interop';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'diag_log.dart';
import 'web_blobs.dart';

/// Si [path] es un resultado guardado como Blob (ver [webBlobs]), lo comparte
/// con el menú del sistema (Web Share API) o, si el navegador no puede, lo
/// descarga. Devuelve false si no hay Blob para esa ruta.
Future<bool> shareRegisteredBlob(String path, {String? mimeType, String? subject, String? text}) async {
  final blob = webBlobs.remove(path);
  if (blob == null) return false;
  final name = p.basename(path);
  final file = web.File(
    [blob].toJS,
    name,
    web.FilePropertyBag(type: mimeType ?? (blob.type.isEmpty ? 'application/octet-stream' : blob.type)),
  );
  final nav = web.window.navigator;
  final data = web.ShareData(files: [file].toJS, title: subject ?? name);
  if (text != null) data.text = text;
  var canShare = false;
  try {
    canShare = nav.canShare(data);
  } catch (_) {}
  if (canShare) {
    try {
      diag('share: menú del sistema para $name (${(blob.size / 1048576).toStringAsFixed(1)} MB)');
      await nav.share(data).toDart;
      return true;
    } catch (e) {
      // Cancelado por el usuario o rechazado (p. ej. archivo muy grande): descargar.
      diag('share: no se pudo compartir ($e), se descarga');
      if ('$e'.contains('AbortError')) return true;
    }
  }
  _download(file, name);
  return true;
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
