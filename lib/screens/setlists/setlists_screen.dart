import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../models/setlist.dart';
import 'setlist_detail_screen.dart';

class SetlistsScreen extends StatelessWidget {
  const SetlistsScreen({super.key});

  Future<void> _confirmDeleteSetlist(BuildContext context, Setlist setlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar setlist'),
          content: Text('¿Eliminar "${setlist.name}"? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      AppData.deleteSetlist(setlist.setlistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppData.setlistsRevision,
      // CORREGIDO: (context, _, __) en lugar de (context, _, _)
      builder: (context, _, __) {
        final setlists = List<Setlist>.of(AppData.setlists); 

        if (setlists.isEmpty) {
          return const Center(
            child: Text(
              'No hay setlists.\nCreá uno con el botón +.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: setlists.length,
          itemBuilder: (context, index) {
            final setlist = setlists[index];

            return Card(
              child: ListTile(
                title: Text(setlist.name),
                subtitle: Text('${setlist.docIds.length} temas'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SetlistDetailScreen(setlistId: setlist.setlistId),
                    ),
                  );
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') {
                      _confirmDeleteSetlist(context, setlist);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}