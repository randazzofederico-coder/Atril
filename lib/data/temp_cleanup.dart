import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/fs/atril_fs.dart';

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
    'atril_pick_',          // archivos elegidos copiados al almacenamiento (web)
  ];

  static Future<void> run({String? docsDir}) async {
    final dirs = <String>{};
    try {
      dirs.add(await fs.tempPath());
    } catch (_) {}
    final systemTemp = fs.systemTempPath;
    if (systemTemp != null) dirs.add(systemTemp);

    var deleted = 0;
    final now = DateTime.now();
    for (final dir in dirs) {
      try {
        for (final entry in await fs.list(dir)) {
          final name = p.basename(entry.path);
          if (!_prefixes.any(name.startsWith)) continue;
          try {
            final modified = await fs.modified(entry.path);
            if (modified == null || now.difference(modified) < minAge) continue;
            if (entry.isDirectory) {
              await fs.deleteDir(entry.path);
            } else {
              await fs.deleteFile(entry.path);
            }
            deleted++;
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('TempCleanup: no se pudo listar $dir: $e');
      }
    }

    // Restos de escrituras atómicas interrumpidas dentro de docs/
    if (docsDir != null) {
      try {
        for (final entry in await fs.list(docsDir)) {
          if (entry.isFile && entry.path.endsWith('.tmp')) {
            try {
              final modified = await fs.modified(entry.path);
              if (modified == null || now.difference(modified) < minAge) continue;
              await fs.deleteFile(entry.path);
              deleted++;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (deleted > 0) debugPrint('TempCleanup: $deleted temporales eliminados');
  }
}
