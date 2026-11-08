part of 'pdf_page_editor_screen.dart';

// Modelo de una página dentro del editor (original, imagen nueva o de otro PDF).

/// Represents one page in the editor.
class _PageEntry {
  /// For original pages: the 0-based index in the source PDF.
  final int? originalPageIndex;

  /// Path to the thumbnail image file (rendered from PDF or from camera/gallery).
  String? thumbnailPath;

  /// For new image pages: the path to the full-resolution edited image.
  final String? imagePath;

  /// Whether this page is still being processed in the background.
  bool isProcessing;

  /// Processing progress (0.0 to 1.0).
  double progress;

  /// For new pages that need background processing (deferred perspective warp).
  final String? originalImagePath;
  ImageEditParams? editParams;

  /// Página tomada de OTRO PDF de la biblioteca (se copia sin pérdida).
  final String? externalPath;
  final int? externalPageIndex;

  bool get isOriginal => originalPageIndex != null;
  bool get isExternal => externalPath != null;
  bool get isNew => imagePath != null || isProcessing || isExternal;

  _PageEntry.original({
    required this.originalPageIndex,
  })  : imagePath = null,
        isProcessing = false,
        progress = 1.0,
        originalImagePath = null,
        editParams = null,
        externalPath = null,
        externalPageIndex = null;

  _PageEntry.image({
    required String this.imagePath,
    this.originalImagePath,
    this.editParams,
    this.isProcessing = false,
  })  : originalPageIndex = null,
        progress = 0.0,
        externalPath = null,
        externalPageIndex = null,
        thumbnailPath = imagePath; // For new images, the image IS the thumbnail

  _PageEntry.external({
    required String this.externalPath,
    required int this.externalPageIndex,
  })  : originalPageIndex = null,
        imagePath = null,
        isProcessing = false,
        progress = 1.0,
        originalImagePath = null,
        editParams = null;
}
