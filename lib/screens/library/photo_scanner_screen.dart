import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_data.dart';
import '../../data/repositories/pdf_generator.dart';
import '../../data/repositories/import_repository.dart';
import 'image_edit_screen.dart';

/// Screen that allows the user to capture photos and compose them into a PDF.
class PhotoScannerScreen extends StatefulWidget {
  final String targetFolderId;

  const PhotoScannerScreen({
    super.key,
    required this.targetFolderId,
  });

  @override
  State<PhotoScannerScreen> createState() => _PhotoScannerScreenState();
}

/// Represents one page in the scanner, with support for background processing.
class _PageEntry {
  final String originalPath;
  String editedPath;
  ImageEditParams params;
  bool isProcessing;
  /// Processing progress (0.0 to 1.0). Updated from the background Isolate.
  double progress;

  _PageEntry({
    required this.originalPath,
    required this.editedPath,
    required this.params,
    this.isProcessing = false,
    this.progress = 0.0,
  });
}

class _PhotoScannerScreenState extends State<PhotoScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<_PageEntry> _pages = [];
  bool _isGenerating = false;

  /// Number of pages currently being processed in background.
  int get _processingCount => _pages.where((p) => p.isProcessing).length;

  // --- Actions ---

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        // Full resolution — no maxWidth or imageQuality limits.
        // Modern phones capture 12MP+ which gives us excellent source data.
      );
      if (photo != null && mounted) {
        final result = await _editImage(photo.path);
        if (result != null && mounted) {
          _addPage(photo.path, result);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        // Full resolution — no maxWidth or imageQuality limits.
      );
      if (images.isNotEmpty && mounted) {
        for (final img in images) {
          if (!mounted) break;
          final result = await _editImage(img.path);
          if (result != null && mounted) {
            _addPage(img.path, result);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imágenes: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Adds a page from the editor result. If the image needs background
  /// processing (deferred perspective warp), kicks it off automatically.
  void _addPage(String originalPath, ImageEditResult result) {
    final page = _PageEntry(
      originalPath: originalPath,
      editedPath: result.editedPath,
      params: result.params,
      isProcessing: result.needsBackgroundProcessing,
    );
    setState(() => _pages.add(page));

    if (result.needsBackgroundProcessing) {
      _processPageInBackground(_pages.length - 1, result);
    }
  }

  /// Runs the deferred perspective warp in a background Isolate with progress.
  Future<void> _processPageInBackground(int index, ImageEditResult result) async {
    try {
      final finalPath = await result.backgroundProcessor!(
        (progress) {
          // Update progress from the background processor
          if (mounted && index < _pages.length) {
            setState(() => _pages[index].progress = progress);
          }
        },
      );
      if (mounted && index < _pages.length) {
        setState(() {
          _pages[index].editedPath = finalPath;
          _pages[index].isProcessing = false;
          _pages[index].progress = 1.0;
        });
      }
    } catch (e) {
      debugPrint('Background processing error for page $index: $e');
      if (mounted && index < _pages.length) {
        // Fallback: use the original image path
        setState(() {
          _pages[index].editedPath = _pages[index].originalPath;
          _pages[index].isProcessing = false;
          _pages[index].progress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error procesando página ${index + 1}'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  /// Opens the image editor and returns the result (path + params).
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

  /// Re-edit using the ORIGINAL image with previous params restored.
  Future<void> _reEditPage(int index) async {
    if (_pages[index].isProcessing) return; // Don't re-edit while processing
    
    final page = _pages[index];
    final result = await _editImage(page.originalPath, page.params);
    if (result != null && mounted) {
      setState(() {
        _pages[index].editedPath = result.editedPath;
        _pages[index].params = result.params;
        _pages[index].isProcessing = result.needsBackgroundProcessing;
        _pages[index].progress = 0.0;
      });
      if (result.needsBackgroundProcessing) {
        _processPageInBackground(index, result);
      }
    }
  }

  void _removePage(int index) {
    setState(() => _pages.removeAt(index));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, item);
    });
  }

  Future<void> _createPdf() async {
    if (_pages.isEmpty) return;

    // Wait for any background processing to finish
    if (_processingCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Esperando procesamiento de $_processingCount página(s)...'),
          duration: const Duration(seconds: 2),
        ),
      );
      // Poll until all processing is done
      while (_pages.any((p) => p.isProcessing)) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }
    }

    // Show name dialog
    final titleCtrl = TextEditingController(
      text: 'Scan ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    );

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre de la partitura',
                icon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_pages.length} página${_pages.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Crear'),
          ),
        ],
      ),
    );

    if (title == null || !mounted) return;
    
    final finalTitle = title.isEmpty 
        ? 'Scan ${DateTime.now().millisecondsSinceEpoch}' 
        : title;

    // Capture data before popping — we'll process in background from the library
    final imagePaths = _pages.map((p) => p.editedPath).toList();
    final targetFolderId = widget.targetFolderId;

    // Pop back to the library immediately
    Navigator.of(context).pop();

    // Generate PDF in background with global progress bar
    _generatePdfInBackground(
      imagePaths: imagePaths,
      title: finalTitle,
      targetFolderId: targetFolderId,
    );
  }

  /// Generates the PDF in the background, reporting progress through
  /// [AppData.backgroundTaskProgress] (the global progress bar in HomeShell).
  static Future<void> _generatePdfInBackground({
    required List<String> imagePaths,
    required String title,
    required String targetFolderId,
  }) async {
    final total = imagePaths.length;
    AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
      0.0,
      'Creando PDF "$title" (0/$total)...',
    );

    try {
      // 1. Generate PDF bytes with per-page progress
      final pdfBytes = await PdfGenerator.generatePdfFromImages(
        imagePaths: imagePaths,
        onProgress: (current, total) {
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
            current / total * 0.85, // 85% of progress is image processing
            'Creando PDF "$title" ($current/$total)...',
          );
        },
      );

      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        0.90,
        'Guardando "$title"...',
      );

      // 2. Save to temp file
      final tempPath = await PdfGenerator.saveTempPdf(pdfBytes);

      // 3. Import into library through the existing pipeline
      await ImportRepository.importPdfFromExternalPath(
        sourcePath: tempPath,
        desiredTitle: title,
        targetFolderId: targetFolderId,
      );

      // 4. Cleanup temp file
      try { await File(tempPath).delete(); } catch (_) {}

      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        1.0,
        '"$title" creado exitosamente',
      );

      // Brief pause so user sees the success message
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      debugPrint('Error generating PDF in background: $e');
      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        0.0,
        'Error creando "$title": $e',
      );
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      AppData.backgroundTaskProgress.value = null;
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Partitura desde Foto'),
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
        ],
      ),
      body: _pages.isEmpty
              ? _buildEmptyState()
              : _buildPageList(),
      bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Camera button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Cámara'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Gallery button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Create PDF button
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pages.isNotEmpty ? _createPdf : null,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Crear PDF'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
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
          Icon(Icons.document_scanner_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Tomá fotos de tu partitura\no seleccionalas de la galería',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tomar Primera Foto'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
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
          key: ValueKey('${page.originalPath}_$index'),
          imagePath: page.editedPath,
          pageNumber: index + 1,
          isProcessing: page.isProcessing,
          progress: page.progress,
          onDelete: () => _removePage(index),
          onTap: () => _reEditPage(index),
        );
      },
    );
  }
}

/// Individual page tile in the scanner list.
class _PageTile extends StatelessWidget {
  final String imagePath;
  final int pageNumber;
  final bool isProcessing;
  final double progress;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _PageTile({
    super.key,
    required this.imagePath,
    required this.pageNumber,
    this.isProcessing = false,
    this.progress = 0.0,
    required this.onDelete,
    required this.onTap,
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
                    Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.red),
                      ),
                    ),
                    if (isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: SizedBox(
                            width: 24, height: 24,
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
              // Info + progress
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Página $pageNumber',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[400]!),
                          ),
                        ),
                      ] else
                        Text(
                          'Tocá para editar',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
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
