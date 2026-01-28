import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../models/score.dart';
import '../models/folder.dart';

class LibraryBrowserSelector extends StatelessWidget {
  final String currentFolderId;
  
  // Callbacks de navegación y acción
  final Function(String folderId) onFolderTap;
  final Function(String docId)? onDocTap;
  
  // Configuración de visualización
  final bool showScores;

  // Selección
  final bool isSelectionMode;
  /// Si es true, permite navegar (ejecutar onFolderTap) incluso cuando isSelectionMode es true.
  final bool allowNavigationInSelectionMode; 

  final Set<String> selectedDocIds;
  final Set<String> selectedFolderIds;
  
  final Function(String docId, bool value)? onDocSelected;
  final Function(String folderId, bool value)? onFolderSelected;

  // Activadores
  final Function(String docId)? onDocLongPress;
  final Function(String folderId)? onFolderLongPress;

  // Acciones de menú contextual
  final Function(String docId, String action)? onDocAction;
  final Function(String folderId, String action)? onFolderAction;

  // Elementos deshabilitados (visual)
  final Set<String> disabledItemIds;

  /// Si es true, muestra las partituras pero grisadas y sin interacción.
  final bool scoresDisabled;

  const LibraryBrowserSelector({
    super.key,
    required this.currentFolderId,
    required this.onFolderTap,
    this.onDocTap,
    this.showScores = true,
    this.isSelectionMode = false,
    this.allowNavigationInSelectionMode = false,
    this.selectedDocIds = const {},
    this.selectedFolderIds = const {},
    this.onDocSelected,
    this.onFolderSelected,
    this.onDocLongPress,
    this.onFolderLongPress,
    this.onDocAction,
    this.onFolderAction,
    this.disabledItemIds = const {},
    this.scoresDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppData.libraryRevision,
      builder: (context, revision, _) {
        
        // 1. CARPETAS
        // Las carpetas suelen ser pocas, pero mantenemos sort local para orden visual.
        final visibleFolders = AppData.folders
            .where((f) => (f.parentId ?? 'root') == currentFolderId)
            .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // 2. PARTITURAS
        // Usamos la lista GLOBAL ya ordenada desde caché.
        List<Score> visibleDocs = [];
        if (showScores) {
          final allSorted = AppData.getLibrarySortedByTitle();
          visibleDocs = allSorted
              .where((s) => s.folderId == currentFolderId)
              .toList();
        }

        if (visibleFolders.isEmpty && visibleDocs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'Carpeta vacía.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          );
        }

        // OPTIMIZACIÓN: CustomScrollView + Slivers para renderizado lazy (ListView.builder)
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // --- SECCIÓN CARPETAS ---
            if (visibleFolders.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildFolderTile(context, visibleFolders[index]),
                  childCount: visibleFolders.length,
                ),
              ),

            // --- SECCIÓN ARCHIVOS ---
            if (visibleDocs.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildScoreTile(context, visibleDocs[index]),
                  childCount: visibleDocs.length,
                ),
              ),

            // Padding final para que el FAB no tape el último elemento
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        );
      },
    );
  }

  // Helper para construir la tile de Carpeta
  Widget _buildFolderTile(BuildContext context, Folder f) {
    final isSelected = selectedFolderIds.contains(f.id);
    final isDisabled = disabledItemIds.contains(f.id);
    
    // Lógica de navegación vs selección
    final bool canTap = !isDisabled && (!isSelectionMode || allowNavigationInSelectionMode);

    Widget? trailingWidget;
    if (isSelectionMode && onFolderSelected != null && !isDisabled) {
      trailingWidget = Checkbox(
        value: isSelected,
        onChanged: (v) => onFolderSelected!(f.id, v ?? false),
      );
    } else if (!isSelectionMode && onFolderAction != null && !isDisabled) {
      trailingWidget = PopupMenuButton<String>(
        onSelected: (action) => onFolderAction!(f.id, action),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Renombrar')),
          PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      );
    }

    return ListTile(
      leading: Icon(Icons.folder, color: isDisabled ? Colors.grey[400] : Colors.amber[700], size: 32),
      title: Text(
        f.name,
        style: TextStyle(
          color: isDisabled ? Colors.grey : null,
          fontStyle: isDisabled ? FontStyle.italic : null,
        ),
      ),
      selected: isSelected,
      enabled: !isDisabled,
      selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      onTap: canTap ? () => onFolderTap(f.id) : null,
      onLongPress: isDisabled ? null : () => onFolderLongPress?.call(f.id),
      trailing: trailingWidget,
    );
  }

  // Helper para construir la tile de Partitura
  Widget _buildScoreTile(BuildContext context, Score doc) {
    final isSelected = selectedDocIds.contains(doc.docId);
    
    // Es disabled si está en la lista negra O si el modo global scoresDisabled está activo
    final isSpecificDisabled = disabledItemIds.contains(doc.docId);
    final isDisabled = isSpecificDisabled || scoresDisabled;

    Widget? trailingWidget;
    
    // Lógica visual:
    if (isSpecificDisabled) {
      // Caso 1: Específico (ej: "Ya agregado al setlist") -> Muestra Check
      trailingWidget = const Icon(Icons.check, color: Colors.grey);
    } else if (scoresDisabled) {
      // Caso 2: Contexto (ej: "Folder Picker") -> Solo gris, sin ícono extra
      trailingWidget = null;
    } else if (isSelectionMode && onDocSelected != null) {
      trailingWidget = Checkbox(
        value: isSelected,
        onChanged: (v) => onDocSelected!(doc.docId, v ?? false),
      );
    } else if (!isSelectionMode && onDocAction != null) {
      trailingWidget = PopupMenuButton<String>(
        onSelected: (action) => onDocAction!(doc.docId, action),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Editar datos')),
          PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      );
    }

    return ListTile(
      leading: Icon(
        Icons.picture_as_pdf, 
        color: isDisabled ? Colors.grey[400] : Colors.redAccent, 
        size: 32
      ),
      
      title: Text(
        doc.title,
        style: TextStyle(
          color: isDisabled ? Colors.grey : null,
          fontStyle: isDisabled ? FontStyle.italic : null,
        ),
      ),
      
      subtitle: doc.author.isNotEmpty 
          ? Text(
              doc.author,
              style: TextStyle(
                color: isDisabled ? Colors.grey : null,
                fontStyle: isDisabled ? FontStyle.italic : null,
              ),
            ) 
          : null,
          
      selected: isSelected,
      enabled: !isDisabled, 
      
      selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      onTap: (isDisabled || onDocTap == null) ? null : () => onDocTap!(doc.docId),
      onLongPress: isDisabled ? null : () => onDocLongPress?.call(doc.docId),
      trailing: trailingWidget,
    );
  }
}