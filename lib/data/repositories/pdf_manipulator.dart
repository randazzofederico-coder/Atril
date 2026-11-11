import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../platform/fs/atril_fs.dart';
import '../../platform/pdf_open.dart';

/// Describes one page in the final edited PDF.
class PageEditEntry {
  /// If non-null, this page comes from the original PDF at this index (0-based).
  final int? originalPageIndex;

  /// If non-null, this page is a new image to be inserted.
  final String? imagePath;

  /// Página de OTRO PDF (copiada sin pérdida, como las originales).
  final String? externalPath;
  final int? externalPageIndex; // 0-based

  const PageEditEntry.original(this.originalPageIndex)
      : imagePath = null,
        externalPath = null,
        externalPageIndex = null;
  const PageEditEntry.image(this.imagePath)
      : originalPageIndex = null,
        externalPath = null,
        externalPageIndex = null;
  const PageEditEntry.external(String this.externalPath, int this.externalPageIndex)
      : originalPageIndex = null,
        imagePath = null;
}

/// Repository for PDF page-level manipulation.
///
/// Provides operations to:
/// - Render individual PDF pages as thumbnail images
/// - Reorder, delete, and insert pages into an existing PDF
class PdfManipulator {
  /// Gets the page count for a PDF file.
  static Future<int> getPageCount(String pdfPath) async {
    try {
      final bytes = await fs.readBytes(pdfPath);
      final doc = PdfDocument(inputBytes: bytes);
      final count = doc.pages.count;
      doc.dispose();
      return count;
    } catch (e) {
      debugPrint('Error getting page count: $e');
      return 0;
    }
  }

  /// Renders a single PDF page to a JPEG thumbnail file.
  ///
  /// Returns the path to the temporary thumbnail file, or null on failure.
  /// Uses pdfrx for rendering, then package:image for JPEG encoding.
  static Future<String?> renderPageThumbnail(
    String pdfPath,
    int pageIndex, {
    double thumbnailWidth = 300,
  }) async {
    try {
      final doc = await openPdfrxDocument(pdfPath);
      if (pageIndex >= doc.pages.length) {
        doc.dispose();
        return null;
      }

      final page = doc.pages[pageIndex];
      final ratio = page.height / page.width;
      final height = thumbnailWidth * ratio;

      final rendered = await page.render(
        fullWidth: thumbnailWidth,
        fullHeight: height,
      );
      if (rendered == null) {
        doc.dispose();
        return null;
      }

      // pdfrx returns pixels in BGRA format
      final rawImg = img.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: rendered.pixels.buffer,
        order: img.ChannelOrder.bgra,
      );
      final jpegBytes = img.encodeJpg(rawImg, quality: 85);

      // Dispose pdfrx resources
      rendered.dispose();
      doc.dispose();

      final thumbPath = p.join(await fs.tempPath(),
          'atril_thumb_${DateTime.now().millisecondsSinceEpoch}_$pageIndex.jpg');
      await fs.writeBytes(thumbPath, jpegBytes);

      return thumbPath;
    } catch (e) {
      debugPrint('Error rendering PDF page thumbnail $pageIndex: $e');
      return null;
    }
  }

  /// Applies edit operations to a PDF and returns the resulting bytes.
  ///
  /// The [pageOrder] list describes the final page sequence. Each entry is
  /// either an original page (by index) or a new image page (by path).
  ///
  /// For original pages, the content is preserved losslessly via
  /// Syncfusion's `PdfTemplate` mechanism.
  static Future<Uint8List> applyEdits({
    required String sourcePdfPath,
    required List<PageEditEntry> pageOrder,
    void Function(int current, int total)? onProgress,
  }) async {
    final sourceBytes = await fs.readBytes(sourcePdfPath);
    final sourceDoc = PdfDocument(inputBytes: sourceBytes);

    final resultDoc = PdfDocument();
    resultDoc.pageSettings.margins.all = 0;

    // PDFs externos abiertos una sola vez cada uno
    final externalDocs = <String, PdfDocument>{};

    void copyPage(PdfPage srcPage) {
      // Copia sin pérdida vía template
      final template = srcPage.createTemplate();
      final pageSize = srcPage.size;
      resultDoc.pageSettings.size = pageSize;
      final newPage = resultDoc.pages.add();
      newPage.graphics.drawPdfTemplate(
        template,
        const ui.Offset(0, 0),
        pageSize,
      );
    }

    final total = pageOrder.length;

    for (int i = 0; i < total; i++) {
      final entry = pageOrder[i];

      if (entry.originalPageIndex != null) {
        // Preserve original page via template (lossless copy)
        copyPage(sourceDoc.pages[entry.originalPageIndex!]);
      } else if (entry.externalPath != null) {
        final ext = externalDocs[entry.externalPath!] ??=
            PdfDocument(inputBytes: await fs.readBytes(entry.externalPath!));
        copyPage(ext.pages[entry.externalPageIndex!]);
      } else if (entry.imagePath != null) {
        // Add new image page (same approach as PdfGenerator)
        await _addImagePage(resultDoc, entry.imagePath!);
      }

      onProgress?.call(i + 1, total);
    }

    // If no pages were produced, add a blank page
    if (resultDoc.pages.count == 0) {
      resultDoc.pageSettings.size = PdfPageSize.a4;
      resultDoc.pages.add();
    }

    final pdfBytes = await resultDoc.save();
    sourceDoc.dispose();
    for (final d in externalDocs.values) {
      d.dispose();
    }
    resultDoc.dispose();

    return Uint8List.fromList(pdfBytes);
  }

  /// Adds a single image as a full-bleed PDF page.
  ///
  /// Replicates the logic from PdfGenerator for consistency.
  static Future<void> _addImagePage(PdfDocument doc, String imagePath) async {
    if (!await fs.fileExists(imagePath)) return;

    final imageBytes = await fs.readBytes(imagePath);
    final PdfBitmap image = PdfBitmap(imageBytes);

    const double pageWidth = 595.0; // A4 width in points
    final double aspectRatio = image.height / image.width;
    final double pageHeight = pageWidth * aspectRatio;

    doc.pageSettings.size = ui.Size(pageWidth, pageHeight);
    final page = doc.pages.add();
    page.graphics.drawImage(
      image,
      ui.Rect.fromLTWH(0, 0, pageWidth, pageHeight),
    );
  }
}
