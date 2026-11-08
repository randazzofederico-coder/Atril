import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Limpieza de archivos temporales que genera la app (backups, exportaciones,
/// extracciones, miniaturas). Corre en segundo plano al iniciar.
///
/// Solo borra archivos con prefijos propios de Atril y con más de [minAge] de
/// antigüedad, para no interferir con un "compartir" que todavía esté leyendo.
class TempCleanup {
  TempCleanup._();

  static const Duration minAge = Duration(hours: 6);

  static const List<String> _prefixes = [
    'backup_atril_',        // .atril generados para compartir
    'Biblioteca_Atril_',    // ZIP de exportación para PC
    'atril_backup_',        // snapshots VACUUM INTO
    'export_work_',         // copias con anotaciones aplicadas
    'restore_extraction_',
    'import_extraction_',
    'setlist_import_',
    'atril_thumb_',         // miniaturas del editor de páginas
    'atril_edit_',          // imágenes intermedias del editor de imagen
    'atril_pdf_opt_',       // JPEG optimizados del generador de PDF
    'atril_scan_',          // PDF del escáner antes de importarlo
  ];

  static Future<void> run({Directory? docsDir}) async {
    final dirs = <Directory>{};
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(Directory.systemTemp);
    } catch (_) {}

    var deleted = 0;
    final now = DateTime.now();
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          final name = p.basename(entity.path);
          if (!_prefixes.any(name.startsWith)) continue;
          try {
            final stat = await entity.stat();
            if (now.difference(stat.modified) < minAge) continue;
            await entity.delete(recursive: true);
            deleted++;
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('TempCleanup: no se pudo listar ${dir.path}: $e');
      }
    }

    // Restos de escrituras atómicas interrumpidas dentro de docs/
    if (docsDir != null && await docsDir.exists()) {
      try {
        await for (final entity in docsDir.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            try {
              final stat = await entity.stat();
              if (now.difference(stat.modified) < minAge) continue;
              await entity.delete();
              deleted++;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (deleted > 0) debugPrint('TempCleanup: $deleted temporales eliminados');
  }
}
