import 'package:web/web.dart' as web;

/// Resultados grandes (ZIP de backup/exportación) que en web se guardan como
/// Blob del navegador en lugar de pasar por IndexedDB: se arman por partes y
/// se comparten/descargan directo, sin duplicar la memoria.
final Map<String, web.Blob> webBlobs = <String, web.Blob>{};
