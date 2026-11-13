import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../platform/picked_files.dart' show cancelPick;

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
                value: state.stage == ImportStage.processing
                    ? state.progress
                    : (state.stage == ImportStage.picking && state.total > 0 ? state.current / state.total : null),
                minHeight: 4,
                backgroundColor: Colors.transparent,
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Icono
                    if (state.stage == ImportStage.picking || state.stage == ImportStage.waiting)
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
                    if (state.stage == ImportStage.processing ||
                        (state.stage == ImportStage.picking && state.total > 1))
                      Text(
                        '${state.current} / ${state.total}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),

                    // Esperando a Drive: se puede abandonar
                    if (state.stage == ImportStage.waiting)
                      TextButton(
                        onPressed: () {
                          cancelPick();
                          AppData.importState.value = const ImportState();
                        },
                        child: const Text('Cancelar'),
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
      case ImportStage.waiting:
        // Chrome baja los archivos de Drive antes de entregarlos y no informa
        // el avance: solo podemos avisar que estamos esperando.
        return 'Esperando a Google Drive… los archivos grandes pueden tardar';
      case ImportStage.picking:
        return 'Preparando archivos...';
      case ImportStage.processing:
        return 'Importando: ${state.currentItemName}';
      case ImportStage.finishing:
        return 'Finalizando...';
      default:
        return '';
    }
  }
}