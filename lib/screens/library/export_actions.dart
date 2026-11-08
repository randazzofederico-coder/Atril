import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../data/backup_manager.dart';
import '../../models/score.dart';
import '../../models/setlist.dart';
import '../../widgets/export_options_dialog.dart';

/// Flujos de UI para compartir/exportar con o sin anotaciones.
///
/// Regla general: si no hay anotaciones involucradas, no se pregunta nada y
/// se exporta el original directamente.
class ExportActions {
  ExportActions._();

  /// Comparte una partitura individual (un solo PDF).
  static Future<void> shareScore(BuildContext context, Score score) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var include = false;
      if (await AppData.hasAnnotations(score.docId)) {
        if (!context.mounted) return;
        final choice = await askIncludeAnnotations(
          context,
          title: 'Compartir "${score.title}"',
        );
        if (choice == null) return;
        include = choice;
      }
      await AppData.sharePdf(score, includeAnnotations: include);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
    }
  }

  /// Comparte un setlist en el [format] indicado.
  static Future<void> shareSetlist(
    BuildContext context,
    Setlist setlist,
    SetlistExportFormat format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var include = false;
      final docIds = AppData.materializeSetlist(setlist).map((s) => s.docId);
      if (await AppData.anyHasAnnotations(docIds)) {
        if (!context.mounted) return;
        final choice = await askIncludeAnnotations(
          context,
          title: 'Compartir "${setlist.name}"',
          withSubtitle: format == SetlistExportFormat.setlist
              ? 'Se importan editables en Atril'
              : 'Las anotaciones quedan dibujadas en los PDFs',
          withoutSubtitle: 'PDFs originales, tal como fueron importados',
        );
        if (choice == null) return;
        include = choice;
      }
      await AppData.shareSetlist(setlist, format: format, includeAnnotations: include);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
    }
  }

  /// Exporta toda la biblioteca como ZIP para PC.
  /// Devuelve `false` si el usuario canceló.
  static Future<bool> exportLibraryZip(BuildContext context) async {
    var include = false;
    final docIds = AppData.library.map((s) => s.docId);
    if (await AppData.anyHasAnnotations(docIds)) {
      if (!context.mounted) return false;
      final choice = await askIncludeAnnotations(
        context,
        title: 'Exportar biblioteca',
        withSubtitle: 'Las anotaciones quedan dibujadas en los PDFs',
        withoutSubtitle: 'PDFs originales, tal como fueron importados',
      );
      if (choice == null) return false;
      include = choice;
    }
    await BackupManager.instance.exportLibraryToZip(includeAnnotations: include);
    return true;
  }
}
