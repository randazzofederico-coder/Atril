import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../widgets/library_browser_selector.dart';
import '../../widgets/folder_creation_dialog.dart';

class FolderPickerScreen extends StatefulWidget {
  /// IDs de las carpetas que se están moviendo.
  /// Estas deben aparecer deshabilitadas para evitar mover una carpeta dentro de sí misma.
  final List<String> ignoreFolderIds;
  
  /// Título de la acción (ej: "Mover 3 items")
  final String actionTitle;

  const FolderPickerScreen({
    super.key,
    required this.ignoreFolderIds,
    this.actionTitle = 'Mover items',
  });

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String _currentFolderId = 'root';
  late final Set<String> _ignoredIdsSet;

  @override
  void initState() {
    super.initState();
    _ignoredIdsSet = widget.ignoreFolderIds.toSet();
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

  void _confirmSelection() {
    // Retornamos el ID de la carpeta que el usuario está viendo actualmente
    Navigator.of(context).pop(_currentFolderId);
  }

  @override
  Widget build(BuildContext context) {
    final bool isRoot = _currentFolderId == 'root';
    
    // Título dinámico
    String title = widget.actionTitle;
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
                onPressed: _navigateUp
              ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18)),
              if (!isRoot)
                const Text(
                  'Toca "Mover aquí" para confirmar',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
          actions: [
            // Botón para crear nueva carpeta en el destino (muy útil al organizar)
            IconButton(
              tooltip: 'Nueva carpeta',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => FolderCreationDialog(parentId: _currentFolderId),
                );
              },
            ),
            const SizedBox(width: 8),
            // Acción principal
            FilledButton(
              onPressed: _confirmSelection,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Mover aquí'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: LibraryBrowserSelector(
          currentFolderId: _currentFolderId,
          onFolderTap: _enterFolder,
          onDocTap: null, // No aplica
          
          showScores: true, // <--- CLAVE: Ocultar partituras
          scoresDisabled: true,
          
          // No necesitamos modo selección, solo navegación.
          isSelectionMode: false,
          
          disabledItemIds: _ignoredIdsSet, // Bloquea entrada a las carpetas origen
        ),
      ),
    );
  }
}