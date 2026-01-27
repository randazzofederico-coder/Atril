import 'package:flutter/material.dart';
import '../data/app_data.dart';

class ImportStatusBar extends StatelessWidget {
  const ImportStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImportState>(
      valueListenable: AppData.importState,
      builder: (context, state, child) {
        // Si no hay actividad, no mostramos nada (altura 0)
        if (!state.isActive) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de progreso
              // Si está en 'picking' (descargando de Drive) es indeterminada (se mueve sola)
              // Si está en 'processing' (importando) muestra el avance real
              LinearProgressIndicator(
                value: state.stage == ImportStage.processing ? state.progress : null,
                minHeight: 4,
                backgroundColor: Colors.transparent,
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Icono
                    if (state.stage == ImportStage.picking)
                       const SizedBox(
                         width: 12, height: 12, 
                         child: CircularProgressIndicator(strokeWidth: 2)
                       )
                    else
                       Icon(Icons.download_rounded, size: 16, color: Theme.of(context).primaryColor),
                    
                    const SizedBox(width: 12),
                    
                    // Texto principal
                    Expanded(
                      child: Text(
                        _getStatusText(state),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Contador (ej: 3 / 10)
                    if (state.stage == ImportStage.processing)
                      Text(
                        '${state.current} / ${state.total}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStatusText(ImportState state) {
    switch (state.stage) {
      case ImportStage.picking:
        return 'Descargando archivos...'; // Esto aparece durante la espera de Drive
      case ImportStage.processing:
        return 'Importando: ${state.currentItemName}';
      case ImportStage.finishing:
        return 'Finalizando...';
      default:
        return '';
    }
  }
}