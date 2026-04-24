import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_data.dart';
import '../../data/repositories/pdf_manipulator.dart';
import '../../models/score.dart';
import 'image_edit_screen.dart';
import 'pdf_picker_screen.dart';

/// Screen for editing the page structure of an existing PDF.
///
/// Allows the user to:
/// - Reorder pages via drag & drop
/// - Delete individual pages
/// - Add new pages from camera, gallery, or another PDF in the library
///
/// The UX mirrors [PhotoScannerScreen] for a consistent experience.
class PdfPageEditorScreen extends StatefulWidget {
  final Score score;

  const PdfPageEditorScreen({
    super.key,
    required this.score,
  });

  @override
  State<PdfPageEditorScreen> createState() => _PdfPageEditorScreenState();
}

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

  bool get isOriginal => originalPageIndex != null;
  bool get isNew => imagePath != null || isProcessing;

  _PageEntry.original({
    required this.originalPageIndex,
    this.thumbnailPath,
  })  : imagePath = null,
        isProcessing = false,
        progress = 1.0,
        originalImagePath = null,
        editParams = null;

  _PageEntry.image({
    required String this.imagePath,
    this.originalImagePath,
    this.editParams,
    this.isProcessing = false,
    this.progress = 0.0,
  })  : originalPageIndex = null,
        thumbnailPath = imagePath; // For new images, the image IS the thumbnail
}

class _PdfPageEditorScreenState extends State<PdfPageEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<_PageEntry> _pages = [];
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadPdfPages();
  }

  /// Loads the existing PDF pages and starts rendering thumbnails.
  Future<void> _loadPdfPages() async {
    final pdfPath = widget.score.filePath;
    if (pdfPath == null) {
      setState(() => _isLoading = false);
      return;
    }

    final pageCount = await PdfManipulator.getPageCount(pdfPath);

    setState(() {
      _pages.clear();
      for (int i = 0; i < pageCount; i++) {
        _pages.add(_PageEntry.original(originalPageIndex: i));
      }
      _isLoading = false;
    });

    // Render thumbnails progressively
    for (int i = 0; i < pageCount; i++) {
      if (!mounted) break;
      final thumbPath = await PdfManipulator.renderPageThumbnail(pdfPath, i);
      if (thumbPath != null && mounted && i < _pages.length) {
        setState(() => _pages[i].thumbnailPath = thumbPath);
      }
    }
  }

  // --- Actions ---

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, item);
      _hasChanges = true;
    });
  }

  void _removePage(int index) {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El PDF debe tener al menos una página'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _pages.removeAt(index);
      _hasChanges = true;
    });
  }

  /// Shows the bottom sheet with options to add new pages.
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Agregar Páginas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.teal),
              title: const Text('Desde Cámara'),
              subtitle: const Text('Tomar foto de una partitura'),
              onTap: () {
                Navigator.pop(ctx);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Desde Galería'),
              subtitle: const Text('Seleccionar imágenes'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Desde otro PDF'),
              subtitle: const Text('Agregar páginas de otro documento'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromPdf();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null && mounted) {
        final result = await _editImage(photo.path);
        if (result != null && mounted) {
          _addNewImagePage(photo.path, result);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty && mounted) {
        for (final img in images) {
          if (!mounted) break;
          final result = await _editImage(img.path);
          if (result != null && mounted) {
            _addNewImagePage(img.path, result);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imágenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens the PDF picker to select another PDF from the library,
  /// then imports all its pages.
  Future<void> _pickFromPdf() async {
    final selectedScore = await Navigator.push<Score>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPickerScreen(
          excludeDocId: widget.score.docId,
        ),
      ),
    );

    if (selectedScore == null || selectedScore.filePath == null || !mounted) {
      return;
    }

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Extrayendo páginas...'),
        duration: Duration(seconds: 1),
      ),
    );

    final sourcePath = selectedScore.filePath!;
    final pageCount = await PdfManipulator.getPageCount(sourcePath);

    if (pageCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron extraer páginas del PDF'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Add pages as "original from external PDF" — we render them to images
    // and insert them as image pages into the editor
    for (int i = 0; i < pageCount; i++) {
      if (!mounted) break;
      final thumbPath = await PdfManipulator.renderPageThumbnail(
        sourcePath,
        i,
        thumbnailWidth: 600, // Higher quality for pages that will be in the final PDF
      );
      if (thumbPath != null && mounted) {
        setState(() {
          _pages.add(_PageEntry.image(imagePath: thumbPath));
          _hasChanges = true;
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$pageCount páginas agregadas de "${selectedScore.title}"')),
      );
    }
  }

  /// Opens the image editor and returns the result.
  Future<ImageEditResult?> _editImage(String originalPath, [ImageEditParams? params]) {
    return Navigator.push<ImageEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditScreen(
          imagePath: originalPath,
          initialParams: params,
        ),
      ),
    );
  }

  /// Adds a new image page from the camera/gallery editor result.
  void _addNewImagePage(String originalPath, ImageEditResult result) {
    final page = _PageEntry.image(
      imagePath: result.editedPath,
      originalImagePath: originalPath,
      editParams: result.params,
      isProcessing: result.needsBackgroundProcessing,
    );
    setState(() {
      _pages.add(page);
      _hasChanges = true;
    });

    if (result.needsBackgroundProcessing) {
      _processPageInBackground(_pages.length - 1, result);
    }
  }

  /// Runs the deferred perspective warp in a background Isolate with progress.
  Future<void> _processPageInBackground(int index, ImageEditResult result) async {
    try {
      final finalPath = await result.backgroundProcessor!(
        (progress) {
          if (mounted && index < _pages.length) {
            setState(() => _pages[index].progress = progress);
          }
        },
      );
      if (mounted && index < _pages.length) {
        setState(() {
          _pages[index] = _PageEntry.image(
            imagePath: finalPath,
            originalImagePath: _pages[index].originalImagePath,
            editParams: _pages[index].editParams,
          );
        });
      }
    } catch (e) {
      debugPrint('Background processing error for page $index: $e');
      if (mounted && index < _pages.length) {
        // Fallback: use the original image
        final origPath = _pages[index].originalImagePath;
        setState(() {
          _pages[index] = _PageEntry.image(
            imagePath: origPath ?? _pages[index].imagePath ?? '',
            originalImagePath: origPath,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error procesando página ${index + 1}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Re-edit a new image page (tap to edit again using the original image).
  Future<void> _reEditNewPage(int index) async {
    final page = _pages[index];
    if (page.isProcessing) return;
    if (page.originalImagePath == null) return;

    final result = await _editImage(page.originalImagePath!, page.editParams);
    if (result != null && mounted) {
      setState(() {
        _pages[index] = _PageEntry.image(
          imagePath: result.editedPath,
          originalImagePath: page.originalImagePath,
          editParams: result.params,
          isProcessing: result.needsBackgroundProcessing,
        );
      });
      if (result.needsBackgroundProcessing) {
        _processPageInBackground(index, result);
      }
    }
  }

  // --- Save ---

  Future<void> _savePdf() async {
    if (_pages.isEmpty) return;

    // Wait for any background processing to finish
    final processingCount = _pages.where((p) => p.isProcessing).length;
    if (processingCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Esperando procesamiento de $processingCount página(s)...'),
          duration: const Duration(seconds: 2),
        ),
      );
      while (_pages.any((p) => p.isProcessing)) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }
    }

    // Check if anything actually changed
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    // Build the edit plan
    final pageOrder = <PageEditEntry>[];
    for (final page in _pages) {
      if (page.isOriginal) {
        pageOrder.add(PageEditEntry.original(page.originalPageIndex));
      } else {
        pageOrder.add(PageEditEntry.image(page.imagePath));
      }
    }

    final score = widget.score;
    final pdfPath = score.filePath!;
    final title = score.title;

    // Pop back immediately
    Navigator.of(context).pop();

    // Generate in background
    _applyEditsInBackground(
      sourcePdfPath: pdfPath,
      pageOrder: pageOrder,
      title: title,
      docId: score.docId,
    );
  }

  /// Applies the edits in the background with global progress reporting.
  static Future<void> _applyEditsInBackground({
    required String sourcePdfPath,
    required List<PageEditEntry> pageOrder,
    required String title,
    required String docId,
  }) async {
    final total = pageOrder.length;
    AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
      0.0,
      'Editando "$title" (0/$total)...',
    );

    try {
      // 1. Generate new PDF bytes
      final pdfBytes = await PdfManipulator.applyEdits(
        sourcePdfPath: sourcePdfPath,
        pageOrder: pageOrder,
        onProgress: (current, total) {
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
            current / total * 0.85,
            'Editando "$title" ($current/$total)...',
          );
        },
      );

      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        0.90,
        'Guardando "$title"...',
      );

      // 2. Write the updated PDF (atomic: write to temp then rename)
      final tempPath = '$sourcePdfPath.tmp';
      await File(tempPath).writeAsBytes(pdfBytes, flush: true);
      await File(tempPath).rename(sourcePdfPath);

      // 3. Invalidate page count cache
      LibraryRepository.invalidatePageCountCache(sourcePdfPath);

      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        1.0,
        '"$title" editado exitosamente',
      );

      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      debugPrint('Error applying PDF edits in background: $e');
      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        0.0,
        'Error editando "$title": $e',
      );
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      AppData.backgroundTaskProgress.value = null;
    }
  }

  // --- Confirmation for discard ---

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Los cambios en las páginas no se guardarán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir Editando'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Editar Páginas',
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            if (_pages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Center(
                  child: Text(
                    '${_pages.length} pág.',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              ),
            if (_hasChanges)
              TextButton.icon(
                onPressed: _savePdf,
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Cargando páginas...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _pages.isEmpty
                ? _buildEmptyState()
                : _buildPageList(),
        bottomNavigationBar: _isLoading
            ? null
            : SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: FilledButton.icon(
                    onPressed: _showAddOptions,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar Páginas'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay páginas.\nAgregá páginas con el botón de abajo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPageList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _pages.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            color: Colors.transparent,
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final page = _pages[index];
        return _PageTile(
          key: ValueKey(
            page.isOriginal
                ? 'orig_${page.originalPageIndex}'
                : 'new_${page.imagePath}_$index',
          ),
          thumbnailPath: page.thumbnailPath,
          pageNumber: index + 1,
          isOriginal: page.isOriginal,
          isProcessing: page.isProcessing,
          progress: page.progress,
          onDelete: () => _removePage(index),
          onTap: page.isNew && page.originalImagePath != null
              ? () => _reEditNewPage(index)
              : null,
        );
      },
    );
  }
}

/// Individual page tile in the page editor list.
///
/// Visually consistent with `_PageTile` in PhotoScannerScreen.
class _PageTile extends StatelessWidget {
  final String? thumbnailPath;
  final int pageNumber;
  final bool isOriginal;
  final bool isProcessing;
  final double progress;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const _PageTile({
    super.key,
    required this.thumbnailPath,
    required this.pageNumber,
    required this.isOriginal,
    this.isProcessing = false,
    this.progress = 0.0,
    required this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isProcessing ? null : onTap,
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              // Drag handle
              ReorderableDragStartListener(
                index: pageNumber - 1,
                child: Container(
                  width: 40,
                  color: Colors.grey[100],
                  child: const Center(
                    child: Icon(Icons.drag_handle, color: Colors.grey),
                  ),
                ),
              ),
              // Thumbnail
              SizedBox(
                width: 90,
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnailPath != null)
                      Image.file(
                        File(thumbnailPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child:
                                Icon(Icons.broken_image, color: Colors.red),
                          ),
                        ),
                      )
                    else
                      Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Página $pageNumber',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isProcessing) ...[
                        Text(
                          'Procesando... ${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.orange[400],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            minHeight: 3,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.orange[400]!),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            if (!isOriginal) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Nueva',
                                  style: TextStyle(
                                    color: Colors.teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              onTap != null
                                  ? 'Tocá para editar'
                                  : isOriginal
                                      ? 'Página original'
                                      : '',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Delete button
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Eliminar página',
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
