import 'package:flutter/material.dart';
import '../data/app_data.dart';
// Imports removidos por no ser necesarios directos, AppData ya nos da los modelos si se necesitan tipados
// pero aquí usamos dynamic o inferencia.
import '../screens/reader/pdf_viewer_screen.dart';
import '../screens/library/library_screen.dart';

class ScopedSearchDelegate extends SearchDelegate<dynamic> {
  final String scopeFolderId; 

  ScopedSearchDelegate({required this.scopeFolderId});

  @override
  String get searchFieldLabel {
    if (scopeFolderId == 'root') return 'Buscar en biblioteca...';
    final folder = AppData.getFolderById(scopeFolderId);
    return 'Buscar en "${folder?.name ?? '...'}"...';
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final cleanQuery = query.trim().toLowerCase();
    
    if (cleanQuery.isEmpty) {
      return Center(
        child: Text(
          scopeFolderId == 'root' 
              ? 'Buscando globalmente...' 
              : 'Buscando en esta carpeta y subcarpetas...',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    Set<String> validFolderIds;
    if (scopeFolderId == 'root') {
      validFolderIds = {}; 
    } else {
      validFolderIds = AppData.getRecursiveFolderIds(scopeFolderId);
    }

    final matchedFolders = AppData.folders.where((f) {
      if (scopeFolderId != 'root' && !validFolderIds.contains(f.parentId)) {
        return false;
      }
      return f.name.toLowerCase().contains(cleanQuery);
    }).toList();

    final matchedScores = AppData.library.where((s) {
      if (scopeFolderId != 'root') {
        if (!validFolderIds.contains(s.folderId)) return false;
      }
      return s.title.toLowerCase().contains(cleanQuery) || 
             s.author.toLowerCase().contains(cleanQuery);
    }).toList();

    if (matchedFolders.isEmpty && matchedScores.isEmpty) {
      return const Center(child: Text('Sin resultados.'));
    }

    return ListView(
      children: [
        if (matchedFolders.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Carpetas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ...matchedFolders.map((f) => ListTile(
            leading: Icon(Icons.folder, color: Colors.amber[700]),
            title: Text(f.name),
            subtitle: Text(_getParentPath(f.parentId)),
            onTap: () {
              // Navegar: Abrimos LibraryScreen encima
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LibraryScreen(initialFolderId: f.id),
                ),
              );
            },
          )),
        ],

        if (matchedScores.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Partituras', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ...matchedScores.map((s) => ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            title: Text(s.title),
            subtitle: Text(s.author.isNotEmpty ? s.author : _getParentPath(s.folderId)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PdfViewerScreen(
                    docId: s.docId,
                    title: s.title,
                    filePath: s.filePath ?? '',
                  ),
                ),
              );
            },
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'loc') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LibraryScreen(initialFolderId: s.folderId),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'loc',
                  child: Row(children: [Icon(Icons.folder_open), SizedBox(width: 8), Text('Abrir ubicación')]),
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }

  String _getParentPath(String? parentId) {
    if (parentId == null || parentId == 'root') return 'En: Biblioteca';
    final parent = AppData.getFolderById(parentId);
    return 'En: ${parent?.name ?? '...'}';
  }
}