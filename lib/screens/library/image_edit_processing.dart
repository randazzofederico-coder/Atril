part of 'image_edit_screen.dart';

// Procesamiento pesado del editor de imagen (corre en un Isolate):
// recorte con perspectiva (homografía 3x3), rotación, B/N, brillo y contraste.

/// Params passed to the background island for heavy image processing.
class _PerspectiveProcessParams {
  final String sourcePath;
  final String tempPath;
  final int srcW, srcH;
  final int rotation;
  final bool grayscale;
  final double threshold;
  final double brightness;
  final double contrast;
  final Offset cropTL, cropTR, cropBL, cropBR;

  _PerspectiveProcessParams({
    required this.sourcePath,
    required this.tempPath,
    required this.srcW, required this.srcH,
    required this.rotation,
    required this.grayscale,
    required this.threshold,
    required this.brightness,
    required this.contrast,
    required this.cropTL, required this.cropTR,
    required this.cropBL, required this.cropBR,
  });
}

// --- Top-level Isolate Processing ---

/// Message wrapper to pass both params and a SendPort to the isolate.
class _IsolateMessage {
  final _PerspectiveProcessParams params;
  final SendPort sendPort;
  const _IsolateMessage(this.params, this.sendPort);
}

/// Isolate entry point that sends progress updates through the SendPort.
void _processPerspectiveWithProgress(_IsolateMessage msg) {
  try {
    final result = _runPerspectiveWarp(msg.params, msg.sendPort);
    msg.sendPort.send(result); // Send final path as String
  } catch (e) {
    msg.sendPort.send(['error', e.toString()]);
  }
}

/// Core perspective warp logic. Reports progress through [sendPort] if non-null.
String _runPerspectiveWarp(_PerspectiveProcessParams p, SendPort? sendPort) {
  final file = File(p.sourcePath);
  final bytes = file.readAsBytesSync();
  var source = img.decodeImage(bytes);
  if (source == null) throw Exception('No se pudo decodificar la imagen');

  // CRITICAL: Ensure orientation matches Flutter UI view
  source = img.bakeOrientation(source);
  final int realW = source.width;
  final int realH = source.height;

  sendPort?.send(0.05); // 5% — image decoded

  // Warp Quad points back to real pixel coordinates
  final tl = math.Point<double>(p.cropTL.dx * realW, p.cropTL.dy * realH);
  final tr = math.Point<double>(p.cropTR.dx * realW, p.cropTR.dy * realH);
  final bl = math.Point<double>(p.cropBL.dx * realW, p.cropBL.dy * realH);
  final br = math.Point<double>(p.cropBR.dx * realW, p.cropBR.dy * realH);

  // Adaptive output resolution based on source image size.
  final double sourceMegapixels = realW * realH / 1e6;
  final int outW, outH;
  if (sourceMegapixels >= 8) {
    outW = 2480; outH = 3508; // 300 DPI A4
  } else if (sourceMegapixels >= 4) {
    outW = 2067; outH = 2923; // 250 DPI A4
  } else {
    outW = 1654; outH = 2339; // 200 DPI A4
  }

  // 1. Calculate Homography Matrix H (3x3)
  final h = _calculateHomography(
    const math.Point(0.0, 0.0), math.Point(outW.toDouble(), 0.0),
    math.Point(outW.toDouble(), outH.toDouble()), math.Point(0.0, outH.toDouble()),
    tl, tr, br, bl,
  );

  // 2. Perform Perspective Warp with progress reporting
  //    The warp is ~80% of total processing time.
  final result = img.Image(width: outW, height: outH);
  final int progressInterval = (outH / 20).ceil(); // Report ~20 times
  for (int v = 0; v < outH; v++) {
    for (int u = 0; u < outW; u++) {
      final double denominator = h[6] * u + h[7] * v + 1.0;
      final double x = (h[0] * u + h[1] * v + h[2]) / denominator;
      final double y = (h[3] * u + h[4] * v + h[5]) / denominator;

      if (x >= 0 && x < realW - 1 && y >= 0 && y < realH - 1) {
        final pixel = source.getPixelInterpolate(x, y, interpolation: img.Interpolation.cubic);
        result.setPixel(u, v, pixel);
      }
    }
    // Report progress: 5% (decode) + 80% (warp) = 5..85%
    if (v % progressInterval == 0) {
      sendPort?.send(0.05 + 0.80 * (v / outH));
    }
  }

  sendPort?.send(0.85); // Warp complete

  // 3. Apply Filters
  if (p.brightness != 0 || p.contrast != 0) {
    img.adjustColor(
      result,
      brightness: 1.0 + (p.brightness / 100.0),
      contrast: 1.0 + (p.contrast / 100.0),
    );
  }

  if (p.grayscale) {
    img.grayscale(result);
    img.luminanceThreshold(result, threshold: p.threshold / 255.0);
  }

  sendPort?.send(0.90); // Filters done

  // Rotation (if needed)
  var finalResult = result;
  if (p.rotation != 0) {
    finalResult = img.copyRotate(result, angle: (p.rotation % 4) * 90);
  }

  // Save as JPEG quality 95
  final outBytes = img.encodeJpg(finalResult, quality: 95);
  final outFile = File(p.tempPath);
  outFile.writeAsBytesSync(outBytes);

  sendPort?.send(0.99); // Encoding done

  return p.tempPath;
}

/// Solves for the 8 coefficients of the 3x3 homography matrix (h22 = 1).
/// Maps (u,v) in target square to (x,y) in source quadrilateral.
List<double> _calculateHomography(
    math.Point<double> t0, math.Point<double> t1, math.Point<double> t2, math.Point<double> t3,
    math.Point<double> s0, math.Point<double> s1, math.Point<double> s2, math.Point<double> s3) {
  
  // Matrix A (8x8) and vector B (8x1) for the linear system A * h = B
  final List<List<double>> a = List.generate(8, (_) => List.filled(8, 0.0));
  final List<double> b = List.filled(8, 0.0);

  final targets = [t0, t1, t2, t3];
  final sources = [s0, s1, s2, s3];

  for (int i = 0; i < 4; i++) {
    final ui = targets[i].x;
    final vi = targets[i].y;
    final xi = sources[i].x;
    final yi = sources[i].y;

    // Equation for X: h00*u + h01*v + h02 - h20*u*x - h21*v*x = x
    a[i * 2][0] = ui; a[i * 2][1] = vi; a[i * 2][2] = 1.0;
    a[i * 2][6] = -ui * xi; a[i * 2][7] = -vi * xi;
    b[i * 2] = xi;

    // Equation for Y: h10*u + h11*v + h12 - h20*u*y - h21*v*y = y
    a[i * 2 + 1][3] = ui; a[i * 2 + 1][4] = vi; a[i * 2 + 1][5] = 1.0;
    a[i * 2 + 1][6] = -ui * yi; a[i * 2 + 1][7] = -vi * yi;
    b[i * 2 + 1] = yi;
  }

  // Solve using Gaussian elimination
  return _solveLinearSystem(a, b);
}

/// Simple 8x8 Gaussian elimination solver with pivoting.
List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
  final int n = b.length;
  for (int i = 0; i < n; i++) {
    // Pivot selection
    int max = i;
    for (int k = i + 1; k < n; k++) {
      if (a[k][i].abs() > a[max][i].abs()) max = k;
    }
    // Swap rows
    final tempA = a[i]; a[i] = a[max]; a[max] = tempA;
    final tempB = b[i]; b[i] = b[max]; b[max] = tempB;

    // Pivot
    for (int k = i + 1; k < n; k++) {
      final double factor = a[k][i] / a[i][i];
      b[k] -= factor * b[i];
      for (int j = i; j < n; j++) {
        a[k][j] -= factor * a[i][j];
      }
    }
  }

  // Back substitution
  final List<double> x = List.filled(n, 0.0);
  for (int i = n - 1; i >= 0; i--) {
    double sum = 0.0;
    for (int j = i + 1; j < n; j++) {
      sum += a[i][j] * x[j];
    }
    x[i] = (b[i] - sum) / a[i][i];
  }
  return x;
}
