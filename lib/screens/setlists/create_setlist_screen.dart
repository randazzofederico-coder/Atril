import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../models/setlist.dart';
import '../../widgets/library_browser_selector.dart';

class CreateSetlistScreen extends StatefulWidget {
  const CreateSetlistScreen({super.key});

  @override
  State<CreateSetlistScreen> createState() => _CreateSetlistScreenState();
}

class _CreateSetlistScreenState extends State<CreateSetlistScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedDocIds = {};
  final Set<String> _selectedFolderIds = {};
  final List<String> _selectionOrder = [];
  bool _saving = false;

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

  void _onFolderSelected(String id, bool value) {
    setState(() {
      if (value) {
        _selectedFolderIds.add(id);
        _selectionOrder.add(id);
      } else {
        _selectedFolderIds.remove(id);
        _selectionOrder.remove(id);
      }
    });
  }

  Future<void> _create() async {
    if (_saving) return;

    final desired = _nameController.text.trim();
    final name = AppData.uniqueSetlistName(desired);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre para el setlist.')),
      );
      return;
    }

    final finalDocIds = AppData.getFlatDocIdsFromOrderedSelection(_selectionOrder);
    if (finalDocIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná al menos 1 tema.')),
      );
      return;
    }

    final setlist = Setlist(
      setlistId: AppData.newSetlistId(),
      name: name,
      docIds: finalDocIds,
    );

    setState(() => _saving = true);
    try {
      await AppData.addSetlist(setlist);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text(isRoot ? 'Crear setlist' : AppData.getFolderById(_currentFolderId)?.name ?? 'Carpeta'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _create,
              child: Text(_saving ? 'Guardando…' : 'Crear'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del setlist',
                  border: OutlineInputBorder(),
                ),
                autofocus: isRoot, 
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            const Divider(height: 1),
            
            Expanded(
              child: LibraryBrowserSelector(
                currentFolderId: _currentFolderId,
                onFolderTap: _enterFolder,
                
                // MODO SELECCIÓN + NAVEGACIÓN (Picker Mode)
                isSelectionMode: true,
                allowNavigationInSelectionMode: true, // <--- FIX AQUÍ
                
                selectedDocIds: _selectedDocIds,
                selectedFolderIds: _selectedFolderIds,
                
                onDocSelected: _onDocSelected,
                onFolderSelected: _onFolderSelected,
                
                onDocTap: (docId) => _onDocSelected(docId, !_selectedDocIds.contains(docId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}