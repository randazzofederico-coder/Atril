import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../widgets/library_browser_selector.dart';
import '../../widgets/library_breadcrumbs.dart';
import '../../widgets/folder_creation_dialog.dart';
import '../../widgets/import_status_bar.dart'; 
import '../reader/pdf_viewer_screen.dart';
import '../../widgets/scoped_search_delegate.dart';
import '../settings/settings_screen.dart';
import 'library_actions.dart'; // <--- Importamos la nueva lógica

class LibraryScreen extends StatefulWidget {
  final String? initialFolderId;
  const LibraryScreen({
    super.key, 
    this.initialFolderId
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<String> _historyStack = [];
  String _currentFolderId = 'root';

  bool _isSelectionMode = false;
  final Set<String> _selectedDocIds = {};
  final Set<String> _selectedFolderIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialFolderId != null) {
      _currentFolderId = widget.initialFolderId!;
    }
  }

  // ---------------------------------------------------------------------------
  // NAVEGACIÓN
  // ---------------------------------------------------------------------------
  
  bool get _canGoBack => _historyStack.isNotEmpty || _currentFolderId != 'root';

  void _pushHistoryAndNavigate(String folderId) {
    if (_isSelectionMode) return;
    setState(() {
      _historyStack.add(_currentFolderId);
      _currentFolderId = folderId;
    });
  }

  void _navigateToSpecificFolder(String targetId) {
    if (_isSelectionMode) return;
    if (targetId == _currentFolderId) return;
    setState(() {
      _historyStack.add(_currentFolderId);
      _currentFolderId = targetId;
    });
  }

  Future<bool> _handleBack() async {
    if (_isSelectionMode) {
      _exitSelectionMode();
      return false;
    }
    
    if (_historyStack.isNotEmpty) {
      setState(() {
        _currentFolderId = _historyStack.removeLast();
      });
      return false;
    }
    
    if (_currentFolderId != 'root') {
       final current = AppData.getFolderById(_currentFolderId);
       if (current?.parentId != null) {
          setState(() {
             _currentFolderId = current!.parentId!;
          });
          return false;
       } else {
          setState(() {
            _currentFolderId = 'root';
          });
          return false;
       }
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // GESTIÓN DE SELECCIÓN
  // ---------------------------------------------------------------------------
  void _enterSelectionMode({String? initialDocId, String? initialFolderId}) {
    setState(() {
      _isSelectionMode = true;
      if (initialDocId != null) _selectedDocIds.add(initialDocId);
      if (initialFolderId != null) _selectedFolderIds.add(initialFolderId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedDocIds.clear();
      _selectedFolderIds.clear();
    });
  }

  void _toggleDocSelection(String docId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedDocIds.add(docId);
      } else {
        _selectedDocIds.remove(docId);
      }
    });
  }

  void _toggleFolderSelection(String folderId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedFolderIds.add(folderId);
      } else {
        _selectedFolderIds.remove(folderId);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PUENTES A LIBRARY_ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _deleteSelected() async {
    final deleted = await LibraryActions.deleteSelectedItems(
      context: context, 
      docIds: _selectedDocIds.toList(), 
      folderIds: _selectedFolderIds.toList()
    );
    if (deleted) _exitSelectionMode();
  }

  Future<void> _createSetlist() async {
    final created = await LibraryActions.createSetlistFromSelection(
      context: context, 
      docIds: _selectedDocIds.toList(), 
      folderIds: _selectedFolderIds.toList()
    );
    if (created) _exitSelectionMode();
  }

  Future<void> _moveSelected() async {
    final moved = await LibraryActions.moveSelectedItems(
      context: context, 
      docIds: _selectedDocIds.toList(), 
      folderIds: _selectedFolderIds.toList()
    );
    if (moved) _exitSelectionMode();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    PreferredSizeWidget appBar;
    final bool canSystemPop = !_isSelectionMode && !_canGoBack; 

    if (_isSelectionMode) {
      // --- APPBAR MODO SELECCIÓN ---
      final count = _selectedDocIds.length + _selectedFolderIds.length;
      appBar = AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelectionMode,
        ),
        title: Text('$count'),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_move),
            tooltip: 'Mover a...',
            onPressed: _moveSelected,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Crear Setlist',
            onPressed: _createSetlist,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Eliminar',
            onPressed: _deleteSelected,
          ),
        ],
      );
    } else {
      // --- APPBAR MODO NAVEGACIÓN ---
      appBar = AppBar(
        automaticallyImplyLeading: false, 
        centerTitle: false,
        titleSpacing: 0,
        
        // Back + Breadcrumbs
        title: LibraryBreadcrumbs(
          currentFolderId: _currentFolderId,
          onNavigateTo: _navigateToSpecificFolder,
          onBack: _handleBack,
        ),
        
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar en esta carpeta',
            onPressed: () => showSearch(
               context: context, 
               delegate: ScopedSearchDelegate(scopeFolderId: _currentFolderId),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Importar...',
            onPressed: () => LibraryActions.showImportOptions(context, _currentFolderId),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Nueva carpeta',
            onPressed: () => showDialog(
                 context: context,
                 builder: (_) => FolderCreationDialog(parentId: _currentFolderId),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: () => Navigator.push(
                 context, 
                 MaterialPageRoute(builder: (_) => const SettingsScreen())
            ),
          ),
          const SizedBox(width: 4),
        ],
      );
    }

    return PopScope(
      canPop: canSystemPop,
      onPopInvokedWithResult: (didPop, result) async {
         if (didPop) return;
         await _handleBack();
      },
      child: Scaffold(
        appBar: appBar,
        body: Column(
          children: [
            const ImportStatusBar(),
            Expanded(
              child: LibraryBrowserSelector(
                currentFolderId: _currentFolderId,
                
                isSelectionMode: _isSelectionMode,
                selectedDocIds: _selectedDocIds,
                selectedFolderIds: _selectedFolderIds,
                
                onFolderTap: _pushHistoryAndNavigate,
                
                onDocTap: (docId) {
                   final doc = AppData.getScoreById(docId);
                   if (doc != null) {
                     Navigator.push(
                       context, 
                       MaterialPageRoute(builder: (context) => PdfViewerScreen(
                         docId: doc.docId,
                         title: doc.title,
                         filePath: doc.filePath ?? '',
                       ))
                     );
                   }
                },

                onDocSelected: _toggleDocSelection,
                onFolderSelected: _toggleFolderSelection,

                onDocLongPress: (docId) {
                  if (!_isSelectionMode) _enterSelectionMode(initialDocId: docId);
                },
                onFolderLongPress: (folderId) {
                  if (!_isSelectionMode) _enterSelectionMode(initialFolderId: folderId);
                },

                // LÓGICA DELEGADA A LibraryActions
                onFolderAction: (folderId, action) {
                   if (action == 'rename') LibraryActions.renameFolder(context, folderId);
                   if (action == 'delete') LibraryActions.deleteFolderSingle(context, folderId);
                },
                
                onDocAction: (docId, action) {
                   if (action == 'delete') LibraryActions.deleteScore(context, docId);
                   if (action == 'rename') LibraryActions.editScoreMetadata(context, docId);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}