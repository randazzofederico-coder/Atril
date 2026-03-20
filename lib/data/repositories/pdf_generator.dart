import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Generates a PDF from a list of image file paths.
class PdfGenerator {
  /// Creates a PDF from images and returns the raw bytes.
  ///
  /// Each image becomes a full page. Images are fitted to A4 width (595pt)
  /// with proportional height.
  static Future<Uint8List> generatePdfFromImages({
    required List<String> imagePaths,
  }) async {
    final document = PdfDocument();
    
    // Configure default page settings
    document.pageSettings.margins.all = 0;
    
    // Remove the default first page that PdfDocument creates
    if (document.pages.count > 0) {
      document.pages.removeAt(0);
    }

    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        
        final bytes = await file.readAsBytes();
        final PdfBitmap image = PdfBitmap(bytes);
        
        // Calculate page size based on image aspect ratio
        const double pageWidth = 595.0; // A4 width in points
        final double aspectRatio = image.height / image.width;
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
      } catch (e) {
        debugPrint('Error processing image $path: $e');
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
