import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../models/setlist.dart';
import '../../widgets/score_import_logic.dart';
import 'folder_picker_screen.dart';

/// Clase utilitaria estática para manejar las acciones de negocio de la Biblioteca.
/// Esto descarga de responsabilidad a la pantalla principal (UI).
class LibraryActions {

  // ---------------------------------------------------------------------------
  // IMPORTACIÓN
  // ---------------------------------------------------------------------------
  
  static void showImportOptions(BuildContext context, String currentFolderId) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Importar'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              ScoreImportLogic.pickAndImportFiles(context, currentFolderId);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.description, color: Colors.blueGrey),
                  SizedBox(width: 12),
                  Text('Archivos PDF'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              ScoreImportLogic.pickAndImportFolder(context, currentFolderId);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.amber),
                  SizedBox(width: 12),
                  Text('Carpeta completa'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GESTIÓN DE CARPETAS (CRUD)
  // ---------------------------------------------------------------------------

  static Future<void> editScoreMetadata(BuildContext context, String docId) async {
    final doc = AppData.getScoreById(docId);
    if (doc == null) return;
    
    final titleCtrl = TextEditingController(text: doc.title);
    final authorCtrl = TextEditingController(text: doc.author);

    // Usamos un Form simple dentro del diálogo
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar datos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Título',
                icon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: authorCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Compositor / Autor',
                icon: Icon(Icons.person),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), 
            child: const Text('Cancelar')
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Guardar')
          ),
        ],
      ),
    );

    if (changed == true) {
       final newTitle = titleCtrl.text.trim();
       // Si el usuario borra el título, usamos "Sin Título" por seguridad
       final finalTitle = newTitle.isEmpty ? 'Sin Título' : newTitle;
       final finalAuthor = authorCtrl.text.trim();

       // Llamamos a la nueva función de AppData
       await AppData.updateScoreMetadata(docId, finalTitle, finalAuthor);
    }
  }

  static Future<void> renameFolder(BuildContext context, String folderId) async {
    final folder = AppData.getFolderById(folderId);
    if (folder == null) return;
    
    final controller = TextEditingController(text: folder.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar carpeta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nuevo nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancelar')
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text), 
            child: const Text('Renombrar')
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty) {
       await AppData.renameFolder(folderId, newName.trim());
    }
  }

  static Future<void> deleteFolderSingle(BuildContext context, String folderId) async {
    final folder = AppData.getFolderById(folderId);
    if (folder == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar carpeta'),
        content: Text('¿Eliminar "${folder.name}" y TODO su contenido?\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Eliminar')
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppData.deleteItems(docIds: [], folderIds: [folderId]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carpeta eliminada')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // GESTIÓN DE SCORES (CRUD)
  // ---------------------------------------------------------------------------

  static Future<void> renameScore(BuildContext context, String docId) async {
    final doc = AppData.getScoreById(docId);
    if (doc == null) return;
    
    final controller = TextEditingController(text: doc.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar archivo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Renombrar')),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
       await AppData.renameScore(docId, newName);
    }
  }

  static Future<void> deleteScore(BuildContext context, String docId) async {
    // Confirmación opcional para borrado individual? Por ahora directo o agregar confirmación si deseas.
    // Usaremos confirmación simple para consistencia.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar partitura'),
        content: const Text('¿Eliminar este archivo?\nSe borrarán también sus anotaciones.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
       await AppData.deleteScore(docId);
    }
  }

  // ---------------------------------------------------------------------------
  // ACCIONES MASIVAS (SELECCIÓN)
  // ---------------------------------------------------------------------------

  /// Retorna true si se realizó la eliminación, para que la UI limpie la selección.
  static Future<bool> deleteSelectedItems({
    required BuildContext context,
    required List<String> docIds,
    required List<String> folderIds,
  }) async {
    final count = docIds.length + folderIds.length;
    if (count == 0) return false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar $count elementos seleccionados?\nLas carpetas se borrarán con todo su contenido.'),
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
      await AppData.deleteItems(docIds: docIds, folderIds: folderIds);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elementos eliminados')));
      }
      return true;
    }
    return false;
  }

  /// Retorna true si se creó el setlist, para limpiar selección.
  static Future<bool> createSetlistFromSelection({
    required BuildContext context,
    required List<String> docIds,
    required List<String> folderIds,
  }) async {
    if (docIds.isEmpty && folderIds.isEmpty) return false;
    
    final items = AppData.getFlatDocIdsFromOrderedSelection([...docIds, ...folderIds]);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La selección no contiene partituras.')));
      return false;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Setlist'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nombre del setlist'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      final sName = AppData.uniqueSetlistName(name);
      final newSetlist = Setlist(
        setlistId: AppData.newSetlistId(),
        name: sName,
        docIds: items,
      );
      await AppData.addSetlist(newSetlist);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Setlist "$sName" creado')));
      }
      return true;
    }
    return false;
  }

  /// Retorna true si se movieron los items.
  static Future<bool> moveSelectedItems({
    required BuildContext context,
    required List<String> docIds,
    required List<String> folderIds,
  }) async {
    final count = docIds.length + folderIds.length;
    if (count == 0) return false;

    // 1. Calculamos IDs a ignorar (las carpetas que estamos moviendo)
    final ignoreIds = folderIds.toList();

    // 2. Abrir el Picker
    final targetFolderId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FolderPickerScreen(
          ignoreFolderIds: ignoreIds,
          actionTitle: 'Mover $count items',
        ),
      ),
    );

    // 3. Ejecutar movimiento si hubo selección
    if (targetFolderId != null) {
      try {
        await AppData.moveItems(
          docIds: docIds,
          folderIds: folderIds,
          targetParentId: targetFolderId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$count items movidos correctamente.')),
          );
        }
        return true;
      } catch (e) {
         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error moviendo items: $e'), backgroundColor: Colors.red),
           );
         }
      }
    }
    return false;
  }
}