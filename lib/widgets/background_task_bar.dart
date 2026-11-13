import 'package:flutter/material.dart';

import '../data/app_data.dart';

/// Barra de progreso de las tareas en segundo plano (importar, backup,
/// exportar...). Es la misma en toda la app: va abajo, sobre la navegación.
/// No ocupa lugar cuando no hay ninguna tarea.
class BackgroundTaskBar extends StatelessWidget {
  const BackgroundTaskBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackgroundTaskStatus?>(
      valueListenable: AppData.backgroundTaskProgress,
      builder: (context, status, _) {
        if (status == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: status.indeterminate ? null : status.progress, minHeight: 4),
            Container(
              color: theme.colorScheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      status.message,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!status.indeterminate)
                    Text(
                      status.percentage,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  if (status.onCancel != null)
                    TextButton(onPressed: status.onCancel, child: const Text('Cancelar')),
                ],
              ),
            ),
            if (status.itemLabel != null)
              Container(
                color: theme.colorScheme.surfaceContainer,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.itemLabel!,
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(value: status.itemProgress, minHeight: 2),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
