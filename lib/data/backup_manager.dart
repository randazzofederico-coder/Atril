import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../platform/diag_log.dart';
import '../platform/fs/atril_fs.dart';
import '../platform/share_files.dart';
import '../platform/zip/zip_tools.dart';
import 'app_data.dart';
import 'app_database.dart';
import 'db/db_connection.dart';
import 'repositories/page_edit_repository.dart';

class BackupManager {
  BackupManager._();

  static final BackupManager instance = BackupManager._();

  /// Genera un archivo .atril (ZIP) con la DB y los PDFs y lanza el diálogo de
  /// compartir/guardar. Lanza una excepción si algo falla.
  ///
  /// La DB se copia con `VACUUM INTO` (snapshot consistente aunque la app
  /// esté escribiendo) en lugar de copiar el archivo SQLite "en caliente".
  Future<void> createBackup() async {
    String? dbSnapshot;
    try {
      final docsDir = await AppData.storage.getDocsPath();
      // 0. Feedback inmediato (con delay para render de UI)
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Escaneando biblioteca...');
      await Future.delayed(const Duration(milliseconds: 50));

      final tempDir = await fs.tempPath();

      // 1. Snapshot consistente de la DB
      dbSnapshot = p.join(tempDir, 'atril_backup_${DateTime.now().millisecondsSinceEpoch}.sqlite');
      await fs.deleteFile(dbSnapshot);
      diag('backup: snapshot de la base');
      await snapshotDatabaseTo(AppData.db, dbSnapshot);
      if (!await fs.fileExists(dbSnapshot)) throw Exception("No se pudo copiar la base de datos.");

      // 2. Preparar lista de archivos
      final filesToZip = <ZipEntrySpec>[];
      filesToZip.add(ZipEntrySpec.file(dbSnapshot, kMainDbFileName));

      for (final file in await fs.list(docsDir, recursive: true)) {
        if (file.isFile) {
          // Temporales de escrituras atómicas interrumpidas: no van al backup
          if (file.path.endsWith('.tmp')) continue;
          final filename = p.relative(file.path, from: docsDir).replaceAll('\\', '/');
          filesToZip.add(ZipEntrySpec.file(file.path, 'docs/$filename'));
        }
      }

      // 3. Preparar destino
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'backup_atril_$timestamp.atril';
      final zipFilePath = p.join(tempDir, fileName);

      // 4. Comprimir (en segundo plano) con progreso
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Creando Backup...');
      await ZipTools.zipToFile(
        zipFilePath,
        filesToZip,
        onProgress: (v) => AppData.backgroundTaskProgress.value = BackgroundTaskStatus(v, 'Comprimiendo...'),
      );

      AppData.backgroundTaskProgress.value = null;

      // 6. Exportar
      diag('backup: compartir $fileName');
      await shareFiles([ShareFile(zipFilePath)], text: 'Backup de Atril Digital');
      diag('backup: compartir terminó');

    } catch (e) {
      debugPrint('Error creando backup: $e');
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (dbSnapshot != null) {
        try { await fs.deleteFile(dbSnapshot); } catch (_) {}
      }
    }
  }

  /// Actualiza la barra de progreso global con [label].
  void Function(double) _progress(String label) =>
      (v) => AppData.backgroundTaskProgress.value = BackgroundTaskStatus(v, label);

  /// Restaura un archivo .atril reemplazando la biblioteca actual.
  ///
  /// Es destructivo por diseño, pero seguro ante fallas:
  /// 1. Extrae y VALIDA el backup (integridad SQLite + que se pueda leer)
  ///    antes de tocar nada.
  /// 2. Mueve la DB y los PDFs actuales a una copia de resguardo (`*.restore_bak`).
  /// 3. Instala lo nuevo y reabre la DB.
  /// 4. Si cualquier paso falla, vuelve a poner la biblioteca anterior.
  /// En todos los casos la DB queda abierta al terminar. Lanza si falla.
  ///
  /// Si [extracted] es true, [sourcePath] es un directorio ya armado con la
  /// misma estructura que el ZIP (`atril.sqlite` + `docs/`), p. ej. un
  /// backup bajado de Drive; no se descomprime ni se borra.
  Future<void> restoreBackup(String sourcePath, {bool extracted = false}) async {
    if (!fs.isNative) {
      // En web la base no es un archivo que se pueda mover (ver db_connection_web).
      throw UnsupportedError(
        'Restaurar un backup todavía no está disponible en la versión web. '
        'Usá "Importar backup" para agregarlo a tu biblioteca.',
      );
    }
    final dbFile = await mainDatabasePath();
    final docsDir = await AppData.storage.getDocsPath();
    final sidecars = ['$dbFile-wal', '$dbFile-shm'];

    const bakSuffix = '.restore_bak';
    final dbBak = '$dbFile$bakSuffix';
    final docsBak = '$docsDir$bakSuffix';

    // 1. Unzip en segundo plano (Evita OOM)
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Verificando y extrayendo backup...');
    
    final extractDir = extracted
        ? sourcePath
        : p.join(await fs.tempPath(), 'restore_extraction_${DateTime.now().millisecondsSinceEpoch}');

    try {
      if (!extracted) {
        await fs.createDir(extractDir);
        await ZipTools.unzipToDir(sourcePath, extractDir, onProgress: _progress('Descomprimiendo para restaurar...'));
      }

      // 2. Validar ANTES de tocar la biblioteca actual
      final dbExtracted = p.join(extractDir, kMainDbFileName);
      if (!await fs.fileExists(dbExtracted)) {
        throw Exception("El archivo no es un backup válido de Atril (falta la base de datos).");
      }
      await _validateBackupDb(dbExtracted);

      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Restaurando archivos...');

      // 3. Cerrar DB actual y resguardar lo actual
      await AppData.closeDbForRestore();

      var installed = false;
      try {
        // Limpiar resguardos viejos de un intento anterior
        await fs.deleteFile(dbBak);
        await fs.deleteDir(docsBak);
        for (final s in sidecars) {
          await fs.deleteFile('$s$bakSuffix');
        }

        if (await fs.fileExists(dbFile)) await fs.rename(dbFile, dbBak);
        for (final s in sidecars) {
          if (await fs.fileExists(s)) await fs.rename(s, '$s$bakSuffix');
        }
        if (await fs.dirExists(docsDir)) await fs.rename(docsDir, docsBak);

        // 4. Instalar lo nuevo
        await fs.copy(dbExtracted, dbFile);
        final docsExtracted = p.join(extractDir, 'docs');
        if (await fs.dirExists(docsExtracted)) {
          await _moveDir(docsExtracted, docsDir);
        } else {
          await fs.createDir(docsDir);
        }

        // 5. Reabrir y verificar que carga
        AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Reiniciando base de datos...');
        await AppData.init(forceReopen: true);
        installed = true;
      } catch (e) {
        debugPrint('Error instalando backup, volviendo a la biblioteca anterior: $e');
        await _rollbackRestore(dbFile, docsDir, sidecars, dbBak, docsBak, bakSuffix);
        rethrow;
      } finally {
        if (!installed) {
          // Garantía: la app nunca queda con la DB cerrada
          try { await AppData.init(forceReopen: true); } catch (e) {
            debugPrint('Error reabriendo DB tras restore fallido: $e');
          }
        }
      }

      // 6. Éxito: descartar resguardos y puntos de restauración del editor
      try {
        await fs.deleteFile(dbBak);
        await fs.deleteDir(docsBak);
        for (final s in sidecars) {
          await fs.deleteFile('$s$bakSuffix');
        }
      } catch (e) {
        debugPrint('Warning: no se pudieron borrar los resguardos del restore: $e');
      }
      await PageEditRepository.discardAllUndo();
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (!extracted) { try { await fs.deleteDir(extractDir); } catch (_) {} }
    }
  }

  /// Abre la DB del backup en modo aislado y verifica que esté sana.
  Future<void> _validateBackupDb(String dbFile) async {
    final candidate = AppDatabase(executor: openDatabaseAtPath(dbFile));
    try {
      final result = await candidate.customSelect('PRAGMA integrity_check').get();
      final status = result.isEmpty ? '' : result.first.data.values.first.toString();
      if (status.toLowerCase() != 'ok') {
        throw Exception('La base de datos del backup está dañada ($status).');
      }
      // Que se pueda leer con el esquema actual (corre migraciones sobre la copia)
      await candidate.getAllDocs();
      await candidate.getAllFolders();
    } catch (e) {
      throw Exception('El backup no se puede usar: $e');
    } finally {
      await candidate.close();
    }
  }

  Future<void> _rollbackRestore(
    String dbFile,
    String docsDir,
    List<String> sidecars,
    String dbBak,
    String docsBak,
    String bakSuffix,
  ) async {
    try {
      if (await fs.fileExists(dbBak)) {
        await fs.deleteFile(dbFile);
        await fs.rename(dbBak, dbFile);
      }
      for (final s in sidecars) {
        final b = '$s$bakSuffix';
        if (await fs.fileExists(b)) {
          await fs.deleteFile(s);
          await fs.rename(b, s);
        }
      }
      if (await fs.dirExists(docsBak)) {
        await fs.deleteDir(docsDir);
        await fs.rename(docsBak, docsDir);
      }
    } catch (e) {
      // Si llegamos acá, los resguardos siguen en disco (*.restore_bak).
      debugPrint('ERROR CRÍTICO en rollback del restore: $e');
    }
  }

  /// Mueve un directorio (rename; si falla, copia recursiva).
  Future<void> _moveDir(String from, String to) async {
    try {
      await fs.rename(from, to);
    } catch (e) {
      debugPrint("Rename failed, copying: $e");
      await fs.createDir(to);
      for (final entity in await fs.list(from, recursive: true)) {
        if (entity.isFile) {
          final rel = p.relative(entity.path, from: from);
          await fs.copy(entity.path, p.join(to, rel));
        }
      }
    }
  }

  /// Agrega el contenido de un backup .atril a la biblioteca actual (sin
  /// reemplazar nada) dentro de una carpeta "Backup Importado (fecha)".
  ///
  /// - Todas las escrituras de DB van en una transacción: si algo falla no
  ///   queda una importación a medias, y los PDFs ya copiados se borran.
  /// - Importa carpetas, partituras (incluidas las de la papelera),
  ///   anotaciones y setlists.
  /// - Devuelve un resumen; lanza si la importación falla.
  /// Con [extracted] = true, [sourcePath] es un directorio ya armado (ver [restoreBackup]).
  /// [folderName]: nombre de la carpeta donde se agrega (por defecto "Backup Importado (fecha)").
  Future<ImportBackupReport> importBackup(String sourcePath, {bool extracted = false, String? folderName}) async {
    final extractDir = extracted ? sourcePath : p.join(await fs.tempPath(), 'import_extraction_${DateTime.now().millisecondsSinceEpoch}');
    final copiedFiles = <String>[];

    try {
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Preparando importación...');
      if (!extracted) await fs.createDir(extractDir);

      // 1. Desde un ZIP: extraer SOLO la base. Cada PDF se extrae después
      //    directo a su lugar final en la biblioteca (sin carpeta temporal:
      //    se escribe una sola vez; en web eso evita gigas de escrituras).
      List<String> zipNames = const [];
      if (!extracted) {
        zipNames = await ZipTools.listEntryNames(sourcePath) ?? const [];
        await ZipTools.extractEntries(sourcePath, {kMainDbFileName: p.join(extractDir, kMainDbFileName)});
      }

      // 2. Abrir y validar la DB del backup
      final dbFile = p.join(extractDir, kMainDbFileName);
      if (!await fs.fileExists(dbFile)) throw Exception("Backup inválido (falta la base de datos).");
      await _validateBackupDb(dbFile);

      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Procesando datos...');

      final externalDb = AppDatabase(executor: openDatabaseAtPath(dbFile));
      try {
        final extFolders = await externalDb.getAllFolders();
        final extDocs = await externalDb.getAllDocs();
        final extStrokes = await externalDb.getAllAnnotationStrokes();
        final extSetlists = await externalDb.getAllSetlists();
        final extItems = await externalDb.getAllSetlistItemsOrdered();

        final docsDir = await AppData.storage.getDocsPath();
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        final rootImportId = AppData.newFolderId();

        // 3. Copiar PDFs primero (fuera de la transacción). Se registra cada
        //    copia para poder borrarla si la transacción falla.
        final docIdMap = <String, String>{}; // id en backup -> id nuevo
        final newRelPath = <String, String>{};
        var missingFiles = 0;
        final toExtract = <String, String>{}; // entrada del ZIP -> destino
        for (var i = 0; i < extDocs.length; i++) {
          final d = extDocs[i];
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
            (i + 1) / extDocs.length, 'Copiando PDFs (${i + 1}/${extDocs.length})...');

          // Desde un directorio: ruta del PDF. Desde un ZIP: nombre de la entrada.
          final source = extracted
              ? await _findBackupPdf(extractDir, d.internalRelPath)
              : _findZipEntry(zipNames, d.internalRelPath);
          if (source == null) {
            missingFiles++;
            debugPrint("Advertencia: PDF no encontrado en el backup para '${d.displayName}'");
            continue;
          }
          final newDocId = AppData.newDocId();
          final newFilename = '$newDocId.pdf';
          final dest = p.join(docsDir, newFilename);
          copiedFiles.add(dest);
          if (extracted) {
            // Web: mover desde el temporal de extracción (no duplica los bytes).
            await (fs.isNative ? fs.copy(source, dest) : fs.rename(source, dest));
          } else {
            toExtract[source] = dest;
          }
          docIdMap[d.id] = newDocId;
          newRelPath[d.id] = p.join('docs', newFilename);
        }

        if (toExtract.isNotEmpty) {
          await ZipTools.extractEntries(
            sourcePath,
            toExtract,
            onProgress: _progress('Extrayendo partituras...'),
          );
        }

        // 4. Escrituras de DB en una sola transacción
        AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Guardando en la biblioteca...');
        var annotations = 0;
        var setlists = 0;
        await AppData.db.transaction(() async {
          await AppData.db.createFolder(
            id: rootImportId,
            name: folderName ?? "Backup Importado ($dateStr)",
            parentId: null, // Raíz
            position: 999, // Al final
          );

          // Carpetas: primero IDs, luego padres (el orden de lectura no
          // garantiza que el padre venga antes que el hijo).
          final folderIdMap = <String, String>{'root': rootImportId};
          final parentOf = <String, String>{};
          for (final f in extFolders) {
            if (f.id == 'root') continue;
            folderIdMap[f.id] = AppData.newFolderId();
          }
          for (final f in extFolders) {
            if (f.id == 'root') continue;
            final parent = f.parentId == null ? rootImportId : (folderIdMap[f.parentId] ?? rootImportId);
            await AppData.db.createFolder(
              id: folderIdMap[f.id]!,
              name: f.name,
              parentId: null, // se asigna abajo (evita FK a carpetas aún no creadas)
              position: f.position,
              isDeleted: f.isDeleted,
              deletedAt: f.deletedAt,
            );
            parentOf[f.id] = parent;
          }
          for (final f in extFolders) {
            if (f.id == 'root') continue;
            await AppData.db.setFolderParent(folderIdMap[f.id]!, parentOf[f.id]);
          }

          // Partituras
          for (final d in extDocs) {
            final newDocId = docIdMap[d.id];
            if (newDocId == null) continue;
            await AppData.db.upsertDoc(
              id: newDocId,
              displayName: d.displayName,
              author: d.author ?? '',
              internalRelPath: newRelPath[d.id]!,
              folderId: d.folderId == null ? rootImportId : (folderIdMap[d.folderId] ?? rootImportId),
              isDeleted: d.isDeleted,
              deletedAt: d.deletedAt,
            );
          }

          // Anotaciones (capa global)
          for (final s in extStrokes) {
            final newDocId = docIdMap[s.docId];
            if (newDocId == null) continue;
            if (s.setlistId != null) continue; // capas legacy por setlist: no se usan
            await AppData.db.insertAnnotationStroke(
              AnnotationStrokesTableCompanion.insert(
                id: AppData.newId(prefix: 'stk'),
                docId: newDocId,
                setlistId: const Value(null),
                pageIndex: s.pageIndex,
                tool: s.tool,
                width: s.width,
                pointsJson: s.pointsJson,
                createdAt: s.createdAt,
              ),
            );
            annotations++;
          }

          // Setlists (con nombre único)
          final itemsBySetlist = <String, List<String>>{};
          for (final it in extItems) {
            final newDocId = docIdMap[it.docId];
            if (newDocId == null) continue;
            itemsBySetlist.putIfAbsent(it.setlistId, () => <String>[]).add(newDocId);
          }
          final usedNames = AppData.setlists.map((s) => s.name.toLowerCase()).toSet();
          for (final s in extSetlists) {
            var name = s.name;
            var n = 2;
            while (usedNames.contains(name.toLowerCase())) {
              name = '${s.name} ($n)';
              n++;
            }
            usedNames.add(name.toLowerCase());
            final newId = AppData.newSetlistId();
            await AppData.db.upsertSetlist(id: newId, name: name, notes: s.notes);
            await AppData.db.replaceSetlistItems(
              setlistId: newId,
              orderedDocIds: (itemsBySetlist[s.id] ?? const <String>[]).toSet().toList(),
            );
            setlists++;
          }
        });

        copiedFiles.clear(); // la transacción se confirmó: los PDFs se quedan
        await AppData.refreshLibrary();

        return ImportBackupReport(
          docs: docIdMap.length,
          missingFiles: missingFiles,
          annotations: annotations,
          setlists: setlists,
        );
      } finally {
        await externalDb.close();
      }
    } catch (e) {
      debugPrint("Error importando backup: $e");
      // Rollback de archivos copiados si la DB no se confirmó
      for (final f in copiedFiles) {
        try { await fs.deleteFile(f); } catch (_) {}
      }
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (!extracted) { try { await fs.deleteDir(extractDir); } catch (_) {} }
    }
  }

  /// Nombre de la entrada del ZIP con el PDF de un doc (ruta guardada o
  /// fallback a docs/<basename>), o null si no está.
  String? _findZipEntry(List<String> names, String internalRelPath) {
    final rel = p.posix.normalize(internalRelPath.replaceAll('\\', '/'));
    for (final c in [rel, 'docs/${p.posix.basename(rel)}']) {
      if (names.contains(c)) return c;
    }
    return null;
  }

  /// Busca el PDF de un doc dentro del backup extraído (ruta guardada o
  /// fallback a docs/<basename>). Nunca sale del directorio extraído.
  Future<String?> _findBackupPdf(String extractDir, String internalRelPath) async {
    final root = p.normalize(extractDir);
    final rel = internalRelPath.replaceAll('\\', '/');
    final candidates = [
      p.normalize(p.join(root, rel)),
      p.normalize(p.join(root, 'docs', p.basename(rel))),
    ];
    for (final c in candidates) {
      if (!p.isWithin(root, c)) continue;
      if (await fs.fileExists(c)) return c;
    }
    return null;
  }

  /// Exporta la biblioteca como un ZIP legible para PC.
  ///
  /// Si [includeAnnotations] es `true`, los PDFs con anotaciones se exportan
  /// con las anotaciones aplicadas (copias temporales; los originales no se
  /// modifican).
  /// Lanza una excepción si algo falla (la UI decide cómo mostrarla).
  Future<void> exportLibraryToZip({bool includeAnnotations = false}) async {
    String? workDir;
    try {
      // 1. Preparar destino
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'Biblioteca_Atril_$timestamp.zip';
      final zipFilePath = p.join(await fs.tempPath(), fileName);
      
      // Feedback inmediato
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Escaneando biblioteca...');
      await Future.delayed(const Duration(milliseconds: 50));

      // 2. Preparar lista de archivos
      final filesToZip = <_BackupFileEntry>[];

      // Helper para obtener el path completo de un folder
      String getFolderPath(String? folderId) {
        if (folderId == null) return '';
        final f = AppData.getFolderById(folderId);
        if (f == null) return '';
        final parentPath = getFolderPath(f.parentId);
        final safeName = _sanitizeFilename(f.name);
        return parentPath.isEmpty ? safeName : '$parentPath/$safeName';
      }

      final usedZipPaths = <String>{};
      final docIdByEntry = <_BackupFileEntry, String>{};

      for (final score in AppData.library) {
        if (score.filePath == null) continue;
        if (!await fs.fileExists(score.filePath!)) continue;

        final folderPath = getFolderPath(score.folderId);
        final safeTitle = _sanitizeFilename(score.title);
        
        var baseName = safeTitle;
        if (baseName.toLowerCase().endsWith('.pdf')) {
           baseName = baseName.substring(0, baseName.length - 4);
        }
        String buildPath(String name) =>
            folderPath.isEmpty ? '$name.pdf' : '$folderPath/$name.pdf';

        // Evitar entradas duplicadas en el ZIP (mismo título en la misma carpeta)
        var zipPath = buildPath(baseName);
        var n = 2;
        while (!usedZipPaths.add(zipPath.toLowerCase())) {
          zipPath = buildPath('$baseName ($n)');
          n++;
        }
        
        final entry = _BackupFileEntry(score.filePath!, zipPath);
        filesToZip.add(entry);
        docIdByEntry[entry] = score.docId;
      }

      // 2b. Aplicar anotaciones (copias temporales aplanadas)
      if (includeAnnotations) {
        workDir = await ExportManager.instance.createExportWorkDir();
        final flattened = await ExportManager.instance.flattenAnnotatedDocs(
          { for (final e in filesToZip) docIdByEntry[e]!: e.sourcePath },
          workDir,
        );
        for (final e in filesToZip) {
          final f = flattened[docIdByEntry[e]];
          if (f != null) e.sourcePath = f;
        }
      }

      // 3. Comprimir (en segundo plano) con progreso
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Exportando...');
      await ZipTools.zipToFile(
        zipFilePath,
        [for (final e in filesToZip) ZipEntrySpec.file(e.sourcePath, e.zipPath)],
        onProgress: _progress('Exportando a PC...'),
      );

      AppData.backgroundTaskProgress.value = null;
      await ExportManager.instance.deleteDirQuietly(workDir);

      // 5. Share
      await shareFiles([ShareFile(zipFilePath)], text: 'Exportación de Biblioteca Atril');

    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error exportando biblioteca: $e');
      rethrow;
    } finally {
      await ExportManager.instance.deleteDirQuietly(workDir);
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}

/// Resumen de una importación de backup (merge).
class ImportBackupReport {
  final int docs;
  final int missingFiles;
  final int annotations;
  final int setlists;
  const ImportBackupReport({
    required this.docs,
    required this.missingFiles,
    required this.annotations,
    required this.setlists,
  });

  String get summary {
    final parts = <String>['$docs partitura(s)'];
    if (annotations > 0) parts.add('$annotations anotación(es)');
    if (setlists > 0) parts.add('$setlists setlist(s)');
    var s = 'Importado: ${parts.join(', ')}.';
    if (missingFiles > 0) s += ' $missingFiles PDF(s) no estaban en el backup.';
    return s;
  }
}

// --- HELPERS ---

class _BackupFileEntry {
  /// Mutable: se reemplaza por la copia aplanada al incluir anotaciones.
  String sourcePath;
  final String zipPath;
  _BackupFileEntry(this.sourcePath, this.zipPath);
}
