part of 'pdf_page_editor_screen.dart';

// Tile de una página en la lista del editor de páginas.

/// Individual page tile in the page editor list.
///
/// Visually consistent with `_PageTile` in PhotoScannerScreen.
class _PageTile extends StatelessWidget {
  final String? thumbnailPath;
  final int pageNumber;
  final bool isOriginal;
  final bool hasAnnotations;
  final bool isProcessing;
  final double progress;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const _PageTile({
    super.key,
    required this.thumbnailPath,
    required this.pageNumber,
    required this.isOriginal,
    this.hasAnnotations = false,
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
                        if (hasAnnotations) ...[
                          Row(
                            children: [
                              Icon(Icons.draw_outlined, size: 14, color: Colors.deepPurple[300]),
                              const SizedBox(width: 4),
                              Text(
                                'Con anotaciones',
                                style: TextStyle(
                                  color: Colors.deepPurple[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
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
