import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../models/setlist.dart';
import '../../models/score.dart';
import 'add_to_setlist_screen.dart';
import '../reader/live_setlist_screen.dart';
import '../reader/pdf_viewer_screen.dart';

class SetlistDetailScreen extends StatefulWidget {
  final String setlistId;

  const SetlistDetailScreen({
    super.key,
    required this.setlistId,
  });

  @override
  State<SetlistDetailScreen> createState() => _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends State<SetlistDetailScreen> {
  bool _isEditing = false;

  Setlist? _setlistOrNull() => AppData.getSetlistById(widget.setlistId);

  // --- LÓGICA DE NEGOCIO ---

  Future<void> _confirmDeleteSetlist(Setlist setlist) async {
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar setlist'),
          content: Text('¿Eliminar "${setlist.name}"? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (ok == true) {
      AppData.deleteSetlist(setlist.setlistId);
      nav.pop();
    }
  }

  Future<void> _addToSetlist(Setlist setlist) async {
    final nav = Navigator.of(context);
    final picked = await nav.push<List<String>>(
      MaterialPageRoute(
        builder: (_) => AddToSetlistScreen(
          setlistName: setlist.name,
          existingDocIds: List<String>.from(setlist.docIds),
        ),
      ),
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) return;

    AppData.addDocsToSetlist(setlist.setlistId, picked);
  }

  Future<void> _removeDoc(Setlist setlist, Score score) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Quitar tema'),
          content: Text('¿Quitar "${score.title}" del setlist?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Quitar'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (ok == true) {
      AppData.removeDocFromSetlist(setlist.setlistId, score.docId);
    }
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Ajuste seguro para el padding inferior
    final safeBottom = mq.padding.bottom > mq.viewPadding.bottom ? mq.padding.bottom : mq.viewPadding.bottom;
    final listPadding = EdgeInsets.fromLTRB(12, 12, 12, 12 + safeBottom);

    return ValueListenableBuilder<int>(
      valueListenable: AppData.setlistsRevision,
      builder: (context, _, __) {
        final setlist = _setlistOrNull();
        
        // 1. Estado: Setlist eliminado externamente
        if (setlist == null) {
          return const Scaffold(
            body: Center(child: Text('Setlist no encontrado.')),
          );
        }

        final scores = AppData.materializeSetlist(setlist);

        return Scaffold(
          appBar: AppBar(
            title: Text(setlist.name),
            actions: [
              // Acciones principales
              if (_isEditing) ...[
                IconButton(
                  tooltip: 'Agregar temas',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addToSetlist(setlist),
                ),
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Listo'),
                ),
              ] else ...[
                 IconButton(
                   tooltip: 'Iniciar Modo En Vivo',
                   icon: const Icon(Icons.play_arrow, size: 28),
                   color: Theme.of(context).brightness == Brightness.dark 
                       ? Colors.greenAccent 
                       : Theme.of(context).primaryColor,
                   onPressed: scores.isEmpty 
                    ? null 
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LiveSetlistScreen(setlist: setlist),
                          ),
                        );
                    },
                 ),
                 IconButton(
                   tooltip: 'Editar orden',
                   onPressed: () => setState(() => _isEditing = true),
                   icon: const Icon(Icons.edit),
                 ),
              ],

              // Menú contextual del Setlist
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete_setlist') _confirmDeleteSetlist(setlist);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete_setlist',
                    child: Text('Eliminar setlist'),
                  ),
                ],
              ),
            ],
          ),
          
          body: scores.isEmpty
              ? _EmptyState(onAdd: () => _addToSetlist(setlist))
              : _isEditing
                  // 2. Estado: Modo Edición (Reordenar y Borrar)
                  ? ReorderableListView.builder(
                      padding: listPadding,
                      itemCount: scores.length,
                      onReorder: (oldIndex, newIndex) {
                        AppData.reorderDocInSetlist(setlist.setlistId, oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final score = scores[index];
                        return _EditableScoreTile(
                          key: ValueKey(score.docId),
                          index: index,
                          score: score,
                          onRemove: () => _removeDoc(setlist, score),
                        );
                      },
                    )
                  // 3. Estado: Modo Visualización (Leer y Abrir)
                  : ListView.builder(
                      padding: listPadding,
                      itemCount: scores.length,
                      itemBuilder: (context, index) {
                        // final score = scores[index]; // Unused
                        return _ViewScoreTile(
                          index: index,
                          sourceScores: scores,
                        );
                      },
                    ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGETS EXTRAÍDOS (UI COMPONENTS)
// -----------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Este setlist está vacío.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd, 
            icon: const Icon(Icons.add),
            label: const Text('Agregar temas'),
          )
        ],
      ),
    );
  }
}

class _ViewScoreTile extends StatelessWidget {
  final int index;
  final List<Score> sourceScores;

  const _ViewScoreTile({
    required this.index,
    required this.sourceScores,
  });

  @override
  Widget build(BuildContext context) {
    final score = sourceScores[index];
    final hasPdf = (score.filePath != null && score.filePath!.isNotEmpty);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
        ),
        title: Text(score.title),
        subtitle: Text(hasPdf ? 'PDF' : score.author),
        trailing: hasPdf ? const Icon(Icons.picture_as_pdf, size: 20, color: Colors.grey) : null,
        onTap: !hasPdf
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      sourceScores: sourceScores,
                      initialIndex: index,
                    ),
                  ),
                );
              },
      ),
    );
  }
}

class _EditableScoreTile extends StatelessWidget {
  final int index;
  final Score score;
  final VoidCallback onRemove;

  const _EditableScoreTile({
    super.key,
    required this.index,
    required this.score,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(score.title),
        subtitle: Text(score.author),
        trailing: IconButton(
          tooltip: 'Quitar del setlist',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
      ),
    );
  }
}