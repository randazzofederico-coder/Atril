part of 'image_edit_screen.dart';

// Painters del editor de imagen (vista previa y recorte con perspectiva).

// --- Painters ---

class _ImagePreviewPainter extends CustomPainter {
  final ui.Image image; final ColorFilter colorFilter;
  _ImagePreviewPainter({required this.image, required this.colorFilter});
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..colorFilter = colorFilter;
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }
  @override bool shouldRepaint(_ImagePreviewPainter old) => old.image != image || old.colorFilter != colorFilter;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _PerspectiveCropOverlayPainter extends CustomPainter {
  final Offset cropTL, cropTR, cropBL, cropBR;
  _PerspectiveCropOverlayPainter({required this.cropTL, required this.cropTR, required this.cropBL, required this.cropBR});

  @override void paint(Canvas canvas, Size size) {
    final tl = Offset(cropTL.dx*size.width, cropTL.dy*size.height);
    final tr = Offset(cropTR.dx*size.width, cropTR.dy*size.height);
    final bl = Offset(cropBL.dx*size.width, cropBL.dy*size.height);
    final br = Offset(cropBR.dx*size.width, cropBR.dy*size.height);

    final quadPath = Path()..moveTo(tl.dx,tl.dy)..lineTo(tr.dx,tr.dy)..lineTo(br.dx,br.dy)..lineTo(bl.dx,bl.dy)..close();
    final fullPath = Path()..addRect(Rect.fromLTWH(0,0,size.width,size.height));
    final dimPath = Path.combine(PathOperation.difference, fullPath, quadPath);
    canvas.drawPath(dimPath, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawPath(quadPath, Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2.0);

    final guidePaint = Paint()..color = Colors.white.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (int i=1; i<=2; i++) {
       final t = i/3.0;
       canvas.drawLine(Offset.lerp(tl, bl, t)!, Offset.lerp(tr, br, t)!, guidePaint);
       canvas.drawLine(Offset.lerp(tl, tr, t)!, Offset.lerp(bl, br, t)!, guidePaint);
    }
  }
  @override bool shouldRepaint(_PerspectiveCropOverlayPainter old) => old.cropTL != cropTL || old.cropTR != cropTR;
}
