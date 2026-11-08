import 'package:flutter/material.dart';

import 'annotation_stroke.dart';

/// Constantes visuales de las anotaciones.
///
/// Compartidas entre el painter en pantalla (`AnnotationLayer`) y el
/// exportador que "quema" las anotaciones en el PDF
/// (`PdfAnnotationFlattener`), para que el resultado exportado sea idéntico
/// a lo que el usuario ve.
///
/// Las unidades son las del canvas del visor: el tamaño de la página en
/// puntos PDF (pdfrx usa `page.width/height` en pt para el layout), por lo que
/// se traducen 1:1 a puntos PDF al exportar.
class AnnotationStyle {
  AnnotationStyle._();

  static const double textFontSize = 16;
  static const double stampFontSize = 32;
  static const double highlighterAlpha = 0.40;

  static Color defaultColorForTool(AnnotationTool tool) {
    switch (tool) {
      case AnnotationTool.pen:
        return Colors.black;
      case AnnotationTool.highlighter:
        return Colors.yellow;
      case AnnotationTool.whiteout:
        return Colors.white;
      case AnnotationTool.stamp:
        return Colors.red;
      case AnnotationTool.text:
        return Colors.black;
      case AnnotationTool.eraser:
        return Colors.grey;
    }
  }

  /// Rango del grosor/tamaño (en puntos de página). El selector es
  /// logarítmico: mucha precisión en tamaños chicos.
  static const double minWidth = 0.3;
  static const double maxWidth = 40.0;

  static IconData stampIcon(String stampId) {
    switch (stampId) {
      case 'coda':
        return Icons.music_note;
      case 'segno':
        return Icons.repeat;
      case 'warning':
        return Icons.warning_amber_rounded;
      default:
        return Icons.star;
    }
  }

  static TextPainter textPainter(String text, Color color, {double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: textFontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: 0, maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  static TextPainter stampPainter(String stampId, Color color) {
    final icon = stampIcon(stampId);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: stampFontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp;
  }
}
