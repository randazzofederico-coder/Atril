import 'package:flutter/material.dart';
import '../data/app_data.dart';

class LibraryBreadcrumbs extends StatelessWidget {
  final String currentFolderId;
  final Function(String) onNavigateTo;
  final Future<bool> Function() onBack;

  const LibraryBreadcrumbs({
    super.key,
    required this.currentFolderId,
    required this.onNavigateTo,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    // Construimos la ruta completa desde la carpeta actual hasta root
    List<String> path = [];
    String? ptr = currentFolderId;
    
    // Recorremos hacia arriba hasta llegar a root o null
    while (ptr != null && ptr != 'root') {
      path.add(ptr);
      final f = AppData.getFolderById(ptr);
      ptr = f?.parentId;
    }
    path.add('root'); // Siempre terminamos en root
    
    // Invertimos para mostrar: Root > Padre > Hijo
    final breadcrumbs = path.reversed.toList();
    final isRoot = currentFolderId == 'root';

    return Row(
      children: [
        // --- BOTÓN ATRÁS (O MARGEN SI ES ROOT) ---
        if (!isRoot)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => onBack(),
            tooltip: 'Atrás',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          )
        else
          const SizedBox(width: 16), // Margen izquierdo estándar cuando no hay flecha

        // --- RUTA SCROLLABLE ---
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: false, 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: breadcrumbs.map((fid) {
                final isLast = fid == breadcrumbs.last;
                final folderName = fid == 'root' 
                    ? 'Biblioteca' 
                    : AppData.getFolderById(fid)?.name ?? '???';

                return Row(
                  children: [
                    // Separador ( > ) excepto para el primero
                    if (fid != breadcrumbs.first)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 0),
                        child: Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                      ),
                    
                    // Nombre de la carpeta
                    InkWell(
                      onTap: isLast ? null : () => onNavigateTo(fid),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          folderName,
                          style: TextStyle(
                            fontSize: 18, // Tamaño un poco más grande para el título
                            fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                            color: isLast ? Colors.black : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}