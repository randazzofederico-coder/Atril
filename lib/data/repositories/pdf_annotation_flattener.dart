import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../models/annotation_stroke.dart';
import '../../models/annotation_style.dart';
import 'annotation_repository.dart';

/// "Quema" (flatten) las anotaciones no destructivas de un documento sobre una
/// COPIA del PDF, para poder compartirlo/exportarlo tal como se ve en la app.
///
/// - El PDF original de la biblioteca nunca se modifica.
/// - Trazos (lápiz, resaltador, corrector) y texto Latin-1 se dibujan como
///   vectores con Syncfusion.
/// - Sellos (íconos de MaterialIcons) y texto con caracteres fuera de Latin-1
///   se rasterizan en el main isolate (dart:ui) y se insertan como imagen.
/// - El trabajo pesado (parsear + escribir el PDF) corre en un Isolate.
///
/// Coordenadas: las anotaciones están normalizadas [0..1] respecto de la
/// página tal como se muestra (ya rotada). Syncfusion aplica automáticamente
/// la transformación de `/Rotate` al obtener `page.graphics` de una página
/// cargada, así que dibujamos en el espacio "visible".
class PdfAnnotationFlattener {
  PdfAnnotationFlattener._();

  /// Factor de sobremuestreo para los elementos rasterizados (sellos, etc.).
  static const double _rasterScale = 4.0;

  /// Genera en [outputPath] una copia de [sourcePath] con las anotaciones de
  /// [docId] aplicadas. Si el documento no tiene anotaciones, copia el
  /// original tal cual.
  ///
  /// Devuelve `true` si se aplicaron anotaciones.
  static Future<bool> flattenToFile({
    required String docId,
    required String sourcePath,
    required String outputPath,
  }) async {
    final strokes = await AnnotationRepository.getAnnotationStrokesForDoc(docId);
    if (strokes.isEmpty) {
      await File(sourcePath).copy(outputPath);
      return false;
    }

    // 1. Pre-render (main isolate, necesita dart:ui + fuentes cargadas)
    final rasters = <String, _RasterItem>{};
    for (final s in strokes) {
      if (s.pointsNorm.isEmpty) continue;
      if (s.tool == AnnotationTool.stamp) {
        final color = s.color ?? AnnotationStyle.defaultColorForTool(s.tool);
        rasters[s.id] = await _rasterize(
          AnnotationStyle.stampPainter(s.content ?? '', color),
        );
      } else if (s.tool == AnnotationTool.text) {
        final text = s.content ?? '';
        if (text.isNotEmpty && !_isLatin1(text)) {
          final color = s.color ?? AnnotationStyle.defaultColorForTool(s.tool);
          rasters[s.id] = await _rasterize(AnnotationStyle.textPainter(text, color));
        }
      }
    }

    // 2. Flatten en Isolate
    final pdfBytes = await File(sourcePath).readAsBytes();
    final args = _FlattenArgs(pdfBytes, strokes, rasters);
    final result = await Isolate.run(() => _flattenWorker(args));

    await File(outputPath).writeAsBytes(result, flush: true);
    return true;
  }

  static bool _isLatin1(String text) => text.codeUnits.every((c) => c <= 0xFF);

  static Future<_RasterItem> _rasterize(TextPainter tp) async {
    final w = tp.width <= 0 ? 1.0 : tp.width;
    final h = tp.height <= 0 ? 1.0 : tp.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_rasterScale);
    tp.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();

    final image = await picture.toImage(
      (w * _rasterScale).ceil(),
      (h * _rasterScale).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    return _RasterItem(data!.buffer.asUint8List(), w, h);
  }
}

// =============================================================================
// ISOLATE WORKER
// =============================================================================

class _RasterItem {
  final Uint8List png;
  final double width; // en puntos PDF
  final double height;
  const _RasterItem(this.png, this.width, this.height);
}

class _FlattenArgs {
  final Uint8List pdfBytes;
  final List<AnnotationStroke> strokes;
  final Map<String, _RasterItem> rasters;
  const _FlattenArgs(this.pdfBytes, this.strokes, this.rasters);
}

Uint8List _flattenWorker(_FlattenArgs args) {
  final doc = PdfDocument(inputBytes: args.pdfBytes);
  try {
    final byPage = <int, List<AnnotationStroke>>{};
    for (final s in args.strokes) {
      byPage.putIfAbsent(s.pageIndex, () => <AnnotationStroke>[]).add(s);
    }

    final pageCount = doc.pages.count;
    byPage.forEach((pageIndex, strokes) {
      final i = pageIndex - 1; // pageIndex es 1-based
      if (i < 0 || i >= pageCount) return;

      final page = doc.pages[i];
      final raw = page.size;
      final rot = page.rotation;
      final swapped = rot == PdfPageRotateAngle.rotateAngle90 ||
          rot == PdfPageRotateAngle.rotateAngle270;
      final size = swapped ? Size(raw.height, raw.width) : raw;

      final g = page.graphics;
      for (final s in strokes) {
        _drawItem(g, size, s, args.rasters[s.id]);
      }
    });

    return Uint8List.fromList(doc.saveSync());
  } finally {
    doc.dispose();
  }
}

void _drawItem(PdfGraphics g, Size size, AnnotationStroke s, _RasterItem? raster) {
  if (s.pointsNorm.isEmpty) return;
  final color = s.color ?? AnnotationStyle.defaultColorForTool(s.tool);
  Offset toPage(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

  switch (s.tool) {
    case AnnotationTool.text:
      final text = s.content ?? '';
      if (text.isEmpty) return;
      final pos = toPage(s.pointsNorm.first);
      _withAlpha(g, color.a, () {
        if (raster != null) {
          g.drawImage(
            PdfBitmap(raster.png),
            Rect.fromLTWH(pos.dx, pos.dy, raster.width, raster.height),
          );
        } else {
          g.drawString(
            text,
            PdfStandardFont(
              PdfFontFamily.helvetica,
              AnnotationStyle.textFontSize,
              style: PdfFontStyle.bold,
            ),
            brush: PdfSolidBrush(_pdfColor(color)),
            bounds: Rect.fromLTWH(pos.dx, pos.dy, 0, 0),
          );
        }
      });
      break;

    case AnnotationTool.stamp:
      if (raster == null) return;
      final center = toPage(s.pointsNorm.first);
      g.drawImage(
        PdfBitmap(raster.png),
        Rect.fromLTWH(
          center.dx - raster.width / 2,
          center.dy - raster.height / 2,
          raster.width,
          raster.height,
        ),
      );
      break;

    case AnnotationTool.eraser:
      return; // la goma nunca se guarda como trazo

    case AnnotationTool.pen:
    case AnnotationTool.highlighter:
    case AnnotationTool.whiteout:
      final pts = s.pointsNorm;
      if (pts.length < 2) return;

      final pen = PdfPen(_pdfColor(color), width: s.width)
        ..lineCap = PdfLineCap.round
        ..lineJoin = PdfLineJoin.round;

      final path = PdfPath();
      var prev = toPage(pts.first);
      for (var k = 1; k < pts.length; k++) {
        final cur = toPage(pts[k]);
        path.addLine(prev, cur);
        prev = cur;
      }

      final alpha = s.tool == AnnotationTool.highlighter
          ? AnnotationStyle.highlighterAlpha
          : color.a;
      _withAlpha(g, alpha, () => g.drawPath(path, pen: pen));
      break;
  }
}

void _withAlpha(PdfGraphics g, double alpha, void Function() draw) {
  if (alpha >= 1.0) {
    draw();
    return;
  }
  final state = g.save();
  g.setTransparency(alpha.clamp(0.0, 1.0));
  draw();
  g.restore(state);
}

PdfColor _pdfColor(Color c) {
  final argb = c.toARGB32();
  return PdfColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}
