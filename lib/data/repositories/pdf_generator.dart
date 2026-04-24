import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Parameters for the background image optimization Isolate.
class _ImageOptimizeParams {
  final String sourcePath;
  final String outputPath;

  /// Maximum width in pixels (300 DPI A4 = 2480px).
  final int maxWidth;

  /// JPEG quality (0-100).
  final int jpegQuality;

  const _ImageOptimizeParams({
    required this.sourcePath,
    required this.outputPath,
    this.maxWidth = 2480,
    this.jpegQuality = 92,
  });
}

/// Result from the optimization Isolate.
class _ImageOptimizeResult {
  /// If non-null, use this file (re-encoded). If null, use the original bytes.
  final String? outputPath;
  final int width;
  final int height;
  /// True if the original file was already optimal and should be embedded as-is.
  final bool passThrough;

  const _ImageOptimizeResult({
    this.outputPath,
    required this.width,
    required this.height,
    this.passThrough = false,
  });
}

/// Generates a PDF from a list of image file paths.
class PdfGenerator {
  /// Creates a PDF from images and returns the raw bytes.
  ///
  /// Images that are already JPEG and within resolution limits are embedded
  /// directly (no re-encoding) to avoid quality loss from double JPEG
  /// compression. Only images that need resizing are re-processed.
  ///
  /// [onProgress] is called after each page is processed, with the current
  /// page index (0-based) and the total page count.
  static Future<Uint8List> generatePdfFromImages({
    required List<String> imagePaths,
    void Function(int current, int total)? onProgress,
  }) async {
    final document = PdfDocument();
    
    // Configure default page settings
    document.pageSettings.margins.all = 0;
    
    // Remove the default first page that PdfDocument creates
    if (document.pages.count > 0) {
      document.pages.removeAt(0);
    }

    final int total = imagePaths.length;
    for (int i = 0; i < total; i++) {
      final path = imagePaths[i];
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        
        // Check if we can pass through the image directly or need processing
        final tempDir = Directory.systemTemp;
        final optimizedPath = '${tempDir.path}/atril_pdf_opt_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final optimizeParams = _ImageOptimizeParams(
          sourcePath: path,
          outputPath: optimizedPath,
          maxWidth: 2480,   // 300 DPI A4 width
          jpegQuality: 92,
        );

        final result = await compute(_optimizeImageIsolate, optimizeParams);

        // Use original bytes if pass-through, otherwise use re-encoded file
        final Uint8List imageBytes;
        if (result.passThrough) {
          imageBytes = await file.readAsBytes();
        } else {
          imageBytes = await File(result.outputPath!).readAsBytes();
          // Cleanup optimized temp file
          try { await File(result.outputPath!).delete(); } catch (_) {}
        }

        final PdfBitmap image = PdfBitmap(imageBytes);
        
        // Calculate page size based on image aspect ratio
        const double pageWidth = 595.0; // A4 width in points
        final double aspectRatio = result.height / result.width;
        final double pageHeight = pageWidth * aspectRatio;
        
        // Set page size for the next page to be added
        document.pageSettings.size = PdfPageSize.a4; // Start with A4
        document.pageSettings.size = ui.Size(pageWidth, pageHeight);
        
        final page = document.pages.add();
        
        // Draw image to fill the entire page
        page.graphics.drawImage(
          image,
          ui.Rect.fromLTWH(0, 0, pageWidth, pageHeight),
        );

        // Report progress
        onProgress?.call(i + 1, total);
      } catch (e) {
        debugPrint('Error processing image $path: $e');
        onProgress?.call(i + 1, total);
      }
    }

    // If no pages were added (all images failed), add a blank page
    if (document.pages.count == 0) {
      document.pageSettings.size = PdfPageSize.a4;
      document.pages.add();
    }

    final List<int> pdfBytes = await document.save();
    document.dispose();
    
    return Uint8List.fromList(pdfBytes);
  }

  /// Saves PDF bytes to a temporary file and returns the path.
  static Future<String> saveTempPdf(Uint8List bytes) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/atril_scan_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  }
}

/// Top-level Isolate function for image optimization.
///
/// Smart pass-through: if the source is already a JPEG within resolution
/// limits, returns passThrough=true so the caller embeds the original bytes
/// directly — avoiding quality-degrading double JPEG compression.
_ImageOptimizeResult _optimizeImageIsolate(_ImageOptimizeParams params) {
  final bytes = File(params.sourcePath).readAsBytesSync();
  
  // Detect format: JPEG starts with 0xFF 0xD8
  final bool isJpeg = bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('Failed to decode image: ${params.sourcePath}');

  // Bake EXIF orientation so dimensions are correct
  image = img.bakeOrientation(image);

  // If it's already a JPEG within size limits, pass through without re-encoding
  if (isJpeg && image.width <= params.maxWidth) {
    return _ImageOptimizeResult(
      width: image.width,
      height: image.height,
      passThrough: true,
    );
  }

  // Image needs resizing — re-encode with cubic interpolation for best quality
  if (image.width > params.maxWidth) {
    final double scale = params.maxWidth / image.width;
    final int newHeight = (image.height * scale).round();
    image = img.copyResize(
      image,
      width: params.maxWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );
  }

  // Re-encode as JPEG with controlled quality
  final jpegBytes = img.encodeJpg(image, quality: params.jpegQuality);
  File(params.outputPath).writeAsBytesSync(jpegBytes);

  return _ImageOptimizeResult(
    outputPath: params.outputPath,
    width: image.width,
    height: image.height,
  );
}
