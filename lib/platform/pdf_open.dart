import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'fs/atril_fs.dart';

/// Abre un PDF con pdfrx desde una ruta de [AtrilFs].
///
/// En nativo usa `openFile` (no carga todo en memoria); en web lee los bytes
/// del almacenamiento del navegador y usa `openData`.
Future<pdfrx.PdfDocument> openPdfrxDocument(String path) async {
  if (fs.isNative) return pdfrx.PdfDocument.openFile(path);
  final bytes = await fs.readBytes(path);
  return pdfrx.PdfDocument.openData(bytes, sourceName: path);
}

/// Referencia de documento para `PdfViewer(...)` a partir de una ruta de
/// [AtrilFs]. En nativo es exactamente lo que usa `PdfViewer.file`.
pdfrx.PdfDocumentRef pdfDocumentRefForPath(String path) {
  if (fs.isNative) return pdfrx.PdfDocumentRefFile(path);
  return _AtrilFsDocumentRef(path);
}

/// Carga el PDF desde [AtrilFs] (web). Igualdad por ruta, como
/// `PdfDocumentRefFile`, para que pdfrx comparta el documento cargado.
class _AtrilFsDocumentRef extends pdfrx.PdfDocumentRef {
  const _AtrilFsDocumentRef(this.path);

  final String path;

  @override
  String get sourceName => path;

  @override
  Future<pdfrx.PdfDocument> loadDocument(
    pdfrx.PdfDocumentLoaderProgressCallback progressCallback,
  ) =>
      openPdfrxDocument(path);

  @override
  bool operator ==(Object other) => other is _AtrilFsDocumentRef && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
