import 'package:flutter/material.dart';
import '../data/app_data.dart';

class ImportProgressDialog extends StatelessWidget {
  final Stream<ImportStatus> importStream;

  const ImportProgressDialog({super.key, required this.importStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ImportStatus>(
      stream: importStream,
      builder: (context, snapshot) {
        final status = snapshot.data;
        
        // Si el stream se completó, cerramos automáticamente el diálogo
        if (snapshot.connectionState == ConnectionState.done || (status?.completed ?? false)) {
          // Usamos postFrameCallback para evitar cerrar el diálogo durante el build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop(status?.count ?? 0);
          });
        }

        return PopScope(
          // Evitamos cerrar el diálogo con back mientras trabaja
          canPop: false, 
          child: AlertDialog(
            title: const Text('Importando...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  'Archivos importados: ${status?.count ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  status?.currentFile ?? 'Escaneando...',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}