import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../data/app_database.dart';
import 'package:intl/intl.dart';

class TrashBinScreen extends StatefulWidget {
  const TrashBinScreen({super.key});

  @override
  State<TrashBinScreen> createState() => _TrashBinScreenState();
}

class _TrashBinScreenState extends State<TrashBinScreen> {
  bool _loading = true;
  List<DocsTableData> _deletedDocs = [];
  List<FoldersTableData> _deletedFolders = [];
  
  final Set<String> _selectedDocIds = {};
  final Set<String> _selectedFolderIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    try {
      final docs = await AppData.db.getDeletedDocs();
      final folders = await AppData.db.getDeletedFolders();
      
      // Sort by deletion date (newest first)
      docs.sort((a, b) => (b.deletedAt ?? 0).compareTo(a.deletedAt ?? 0));
      folders.sort((a, b) => (b.deletedAt ?? 0).compareTo(a.deletedAt ?? 0));

      setState(() {
        _deletedDocs = docs;
        _deletedFolders = folders;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando papelera: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _loading = false);
    }
  }

  void _toggleSelection(String id, bool isDoc) {
    setState(() {
      if (isDoc) {
        if (_selectedDocIds.contains(id)) {
          _selectedDocIds.remove(id);
        } else {
          _selectedDocIds.add(id);
        }
      } else {
        if (_selectedFolderIds.contains(id)) {
          _selectedFolderIds.remove(id);
        } else {
          _selectedFolderIds.add(id);
        }
      }
      _isSelectionMode = _selectedDocIds.isNotEmpty || _selectedFolderIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDocIds.clear();
      _selectedFolderIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _restoreSelected() async {
    final count = _selectedDocIds.length + _selectedFolderIds.length;
    if (count == 0) return;

    await AppData.restoreItems(
      docIds: _selectedDocIds.toList(),
      folderIds: _selectedFolderIds.toList(),
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count elementos restaurados.')),
      );
    }
    _clearSelection();
    _loadTrash();
  }

  Future<void> _deletePermanentlySelected() async {
    final count = _selectedDocIds.length + _selectedFolderIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar permanentemente'),
        content: Text('¿Eliminar $count elementos para siempre?\nEsta acción NO se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Eliminar', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppData.permanentlyDeleteItems(
        docIds: _selectedDocIds.toList(),
        folderIds: _selectedFolderIds.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elementos eliminados permanentemente.')),
        );
      }
      _clearSelection();
      _loadTrash();
    }
  }

  Future<void> _emptyTrash() async {
    if (_deletedDocs.isEmpty && _deletedFolders.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar Papelera'),
        content: const Text('¿Eliminar TODOS los elementos de la papelera?\nEsta acción es irreversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Vaciar Todo', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      final docIds = _deletedDocs.map((e) => e.id).toList();
      final folderIds = _deletedFolders.map((e) => e.id).toList();
      
      await AppData.permanentlyDeleteItems(docIds: docIds, folderIds: folderIds);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Papelera vaciada.')),
        );
      }
      _loadTrash();
    }
  }

  String _formatDate(int? ms) {
    if (ms == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final totalTrash = _deletedDocs.length + _deletedFolders.length;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode 
          ? Text('${_selectedDocIds.length + _selectedFolderIds.length} seleccionados')
          : const Text('Papelera'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restaurar',
              onPressed: _restoreSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Eliminar permanentemente',
              onPressed: _deletePermanentlySelected,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
            ),
          ] else ...[
            if (totalTrash > 0)
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                label: const Text('Vaciar', style: TextStyle(color: Colors.redAccent)),
                onPressed: _emptyTrash,
              ),
          ]
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : totalTrash == 0
          ? _buildEmptyState()
          : _buildTrashList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('La papelera está vacía', style: TextStyle(color: Colors.grey, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildTrashList() {
    return ListView(
      children: [
        if (_deletedFolders.isNotEmpty) ...[
           const Padding(
             padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
             child: Text('Carpetas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
           ),
           ..._deletedFolders.map((f) => _buildFolderTile(f)),
        ],
        if (_deletedDocs.isNotEmpty) ...[
           const Padding(
             padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
             child: Text('Partituras', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
           ),
           ..._deletedDocs.map((d) => _buildDocTile(d)),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildFolderTile(FoldersTableData f) {
    final isSelected = _selectedFolderIds.contains(f.id);
    return ListTile(
      leading: Icon(isSelected ? Icons.check_circle : Icons.folder, color: isSelected ? Colors.blue : Colors.amber),
      title: Text(f.name),
      subtitle: Text('Eliminado: ${_formatDate(f.deletedAt)}'),
      selected: isSelected,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(f.id, false);
        } else {
          _showActionSheet(f.id, f.name, false);
        }
      },
      onLongPress: () => _toggleSelection(f.id, false),
    );
  }

  Widget _buildDocTile(DocsTableData d) {
    final isSelected = _selectedDocIds.contains(d.id);
    return ListTile(
      leading: Icon(isSelected ? Icons.check_circle : Icons.description, color: isSelected ? Colors.blue : Colors.blueGrey),
      title: Text(d.displayName),
      subtitle: Text('Eliminado: ${_formatDate(d.deletedAt)}'),
      selected: isSelected,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(d.id, true);
        } else {
          _showActionSheet(d.id, d.displayName, true);
        }
      },
      onLongPress: () => _toggleSelection(d.id, true),
    );
  }

  void _showActionSheet(String id, String name, bool isDoc) {
     showModalBottomSheet(
       context: context,
       builder: (ctx) => SafeArea(
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             ListTile(
               leading: const Icon(Icons.restore, color: Colors.green),
               title: const Text('Restaurar'),
               onTap: () {
                 Navigator.pop(ctx);
                 _restoreSingle(id, isDoc);
               },
             ),
             ListTile(
               leading: const Icon(Icons.delete_forever, color: Colors.red),
               title: const Text('Eliminar permanentemente'),
               onTap: () {
                 Navigator.pop(ctx);
                 _deleteSinglePermanently(id, isDoc, name);
               },
             ),
           ],
         ),
       ),
     );
  }

  Future<void> _restoreSingle(String id, bool isDoc) async {
    await AppData.restoreItems(
      docIds: isDoc ? [id] : [],
      folderIds: isDoc ? [] : [id],
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elemento restaurado.')));
    }
    _loadTrash();
  }

  Future<void> _deleteSinglePermanently(String id, bool isDoc, String name) async {
     final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar permanentemente'),
        content: Text('¿Eliminar "$name" para siempre?\nEsta acción NO se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Eliminar', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
       await AppData.permanentlyDeleteItems(
         docIds: isDoc ? [id] : [],
         folderIds: isDoc ? [] : [id],
       );
       _loadTrash();
    }
  }
}
