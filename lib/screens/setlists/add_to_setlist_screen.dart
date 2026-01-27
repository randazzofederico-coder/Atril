import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../widgets/library_browser_selector.dart';

class AddToSetlistScreen extends StatefulWidget {
  final String setlistName;
  final List<String> existingDocIds;

  const AddToSetlistScreen({
    super.key,
    required this.setlistName,
    required this.existingDocIds,
  });

  @override
  State<AddToSetlistScreen> createState() => _AddToSetlistScreenState();
}

class _AddToSetlistScreenState extends State<AddToSetlistScreen> {
  final Set<String> _selectedDocIds = {};
  final Set<String> _selectedFolderIds = {};
  final List<String> _selectionOrder = [];
  late final Set<String> _existingIdsSet;

  String _currentFolderId = 'root';

  @override
  void initState() {
    super.initState();
    _existingIdsSet = widget.existingDocIds.toSet();
  }

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

  void _onDocSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedDocIds.add(id);
        _selectionOrder.add(id);
      } else {
        _selectedDocIds.remove(id);
        _selectionOrder.remove(id);
      }
    });
  }

  void _onFolderSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedFolderIds.add(id);
        _selectionOrder.add(id);
      } else {
        _selectedFolderIds.remove(id);
        _selectionOrder.remove(id);
      }
    });
  }

  void _confirm() {
    final finalDocIds = AppData.getFlatDocIdsFromOrderedSelection(_selectionOrder);
    final newDocs = finalDocIds.where((id) => !_existingIdsSet.contains(id)).toList();
    Navigator.of(context).pop<List<String>>(newDocs);
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Agregar a "${widget.setlistName}"';
    if (_currentFolderId != 'root') {
      final f = AppData.getFolderById(_currentFolderId);
      title = f?.name ?? 'Carpeta';
    }

    final bool isRoot = _currentFolderId == 'root';

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
                onPressed: _navigateUp
              ),
          title: Text(title),
          actions: [
            TextButton(
              onPressed: (_selectedDocIds.isEmpty && _selectedFolderIds.isEmpty) 
                ? null 
                : _confirm,
              child: const Text('Agregar'),
            ),
          ],
        ),
        body: LibraryBrowserSelector(
          currentFolderId: _currentFolderId,
          onFolderTap: _enterFolder,
          
          // Modo selección forzado con navegación permitida
          isSelectionMode: true,
          allowNavigationInSelectionMode: true, 
          
          selectedDocIds: _selectedDocIds,
          selectedFolderIds: _selectedFolderIds,
          
          // CORRECCIÓN AQUÍ: Usamos el nuevo nombre genérico
          disabledItemIds: _existingIdsSet,
          
          onDocSelected: _onDocSelected,
          onFolderSelected: _onFolderSelected,
          
          // Al tocar, simplemente seleccionamos
          onDocTap: (docId) => _onDocSelected(docId, !_selectedDocIds.contains(docId)),
        ),
      ),
    );
  }
}