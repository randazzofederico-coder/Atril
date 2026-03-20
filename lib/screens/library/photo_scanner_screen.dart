import 'dart:io';

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

class _PhotoScannerScreenState extends State<PhotoScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  /// Edited image paths (what gets put into the PDF).
  final List<String> _imagePaths = [];
  /// Original image paths (used when re-editing to keep full data).
  final List<String> _originalPaths = [];
  /// Edit params per page (so re-edit restores previous settings).
  final List<ImageEditParams> _editParams = [];
  bool _isGenerating = false;

  // --- Actions ---

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (photo != null && mounted) {
        final result = await _editImage(photo.path);
        if (result != null && mounted) {
          setState(() {
            _originalPaths.add(photo.path);
            _imagePaths.add(result.editedPath);
            _editParams.add(result.params);
          });
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
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (images.isNotEmpty && mounted) {
        for (final img in images) {
          if (!mounted) break;
          final result = await _editImage(img.path);
          if (result != null && mounted) {
            setState(() {
              _originalPaths.add(img.path);
              _imagePaths.add(result.editedPath);
              _editParams.add(result.params);
            });
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
    final originalPath = _originalPaths[index];
    final previousParams = _editParams[index];
    final result = await _editImage(originalPath, previousParams);
    if (result != null && mounted) {
      setState(() {
        _imagePaths[index] = result.editedPath;
        _editParams[index] = result.params;
      });
    }
  }

  void _removePage(int index) {
    setState(() {
      _imagePaths.removeAt(index);
      _originalPaths.removeAt(index);
      _editParams.removeAt(index);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final editedItem = _imagePaths.removeAt(oldIndex);
      _imagePaths.insert(newIndex, editedItem);
      final originalItem = _originalPaths.removeAt(oldIndex);
      _originalPaths.insert(newIndex, originalItem);
      final paramsItem = _editParams.removeAt(oldIndex);
      _editParams.insert(newIndex, paramsItem);
    });
  }

  Future<void> _createPdf() async {
    if (_imagePaths.isEmpty) return;

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
              '${_imagePaths.length} página${_imagePaths.length == 1 ? '' : 's'}',
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

    // Generate PDF
    setState(() => _isGenerating = true);

    try {
      // 1. Generate PDF bytes
      final pdfBytes = await PdfGenerator.generatePdfFromImages(
        imagePaths: _imagePaths,
      );

      // 2. Save to temp file
      final tempPath = await PdfGenerator.saveTempPdf(pdfBytes);

      // 3. Import into library through the existing pipeline
      await ImportRepository.importPdfFromExternalPath(
        sourcePath: tempPath,
        desiredTitle: finalTitle,
        targetFolderId: widget.targetFolderId,
      );

      // 4. Cleanup temp file
      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$finalTitle" creado exitosamente')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Partitura desde Foto'),
        actions: [
          if (_imagePaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: Text(
                  '${_imagePaths.length} pág.',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generando PDF...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : _imagePaths.isEmpty
              ? _buildEmptyState()
              : _buildPageList(),
      bottomNavigationBar: _isGenerating
          ? null
          : SafeArea(
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
                        onPressed: _imagePaths.isNotEmpty ? _createPdf : null,
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
      itemCount: _imagePaths.length,
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
        final path = _imagePaths[index];
        return _PageTile(
          key: ValueKey('${path}_$index'),
          imagePath: path,
          pageNumber: index + 1,
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
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _PageTile({
    super.key,
    required this.imagePath,
    required this.pageNumber,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 200,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.red),
                  ),
                ),
              ),
              // Info
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
                      Text(
                        'Tocá para editar',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
