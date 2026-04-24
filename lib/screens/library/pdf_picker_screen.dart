import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../models/score.dart';
import '../../widgets/library_browser_selector.dart';

/// Screen for picking a PDF from the library.
///
/// Used by [PdfPageEditorScreen] when the user wants to import pages
/// from another PDF in the library.
class PdfPickerScreen extends StatefulWidget {
  /// DocId to exclude from the list (the PDF being edited).
  final String? excludeDocId;

  const PdfPickerScreen({
    super.key,
    this.excludeDocId,
  });

  @override
  State<PdfPickerScreen> createState() => _PdfPickerScreenState();
}

class _PdfPickerScreenState extends State<PdfPickerScreen> {
  String _currentFolderId = 'root';

  void _enterFolder(String folderId) {
    setState(() => _currentFolderId = folderId);
  }

  void _navigateUp() {
    if (_currentFolderId == 'root') return;
    final current = AppData.getFolderById(_currentFolderId);
    setState(() {
      _currentFolderId = current?.parentId ?? 'root';
    });
  }

  void _selectDoc(String docId) {
    final score = AppData.getScoreById(docId);
    if (score != null) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRoot = _currentFolderId == 'root';

    String title = 'Seleccionar PDF';
    if (!isRoot) {
      final f = AppData.getFolderById(_currentFolderId);
      title = f?.name ?? 'Carpeta';
    }

    return PopScope(
      canPop: isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _navigateUp();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: isRoot
              ? const CloseButton()
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _navigateUp,
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18)),
              const Text(
                'Tocá un PDF para agregar sus páginas',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        body: LibraryBrowserSelector(
          currentFolderId: _currentFolderId,
          onFolderTap: _enterFolder,
          onDocTap: _selectDoc,
          showScores: true,
          isSelectionMode: false,
          disabledItemIds: widget.excludeDocId != null
              ? {widget.excludeDocId!}
              : const {},
        ),
      ),
    );
  }
}
