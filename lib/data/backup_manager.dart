import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // Worker
import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_data.dart';
import 'app_database.dart';
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
    File? dbSnapshot;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));
      // 0. Feedback inmediato (con delay para render de UI)
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Escaneando biblioteca...');
      await Future.delayed(const Duration(milliseconds: 50));

      final tempDir = await getTemporaryDirectory();

      // 1. Snapshot consistente de la DB
      dbSnapshot = File(p.join(tempDir.path, 'atril_backup_${DateTime.now().millisecondsSinceEpoch}.sqlite'));
      if (await dbSnapshot.exists()) await dbSnapshot.delete();
      await AppData.db.customStatement('VACUUM INTO ?', [dbSnapshot.path]);
      if (!await dbSnapshot.exists()) throw Exception("No se pudo copiar la base de datos.");

      // 2. Preparar lista de archivos
      final filesToZip = <_BackupFileEntry>[];
      filesToZip.add(_BackupFileEntry(dbSnapshot.path, 'atril.sqlite'));

      if (await docsDir.exists()) {
        // Async list para no congelar UI
        final files = await docsDir.list(recursive: true).toList();
        for (final file in files) {
          if (file is File) {
            // Temporales de escrituras atómicas interrumpidas: no van al backup
            if (file.path.endsWith('.tmp')) continue;
            final filename = p.relative(file.path, from: docsDir.path).replaceAll('\\', '/');
            filesToZip.add(_BackupFileEntry(file.path, 'docs/$filename'));
          }
        }
      }

      // 3. Preparar destino
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'backup_atril_$timestamp.atril';
      final zipFilePath = p.join(tempDir.path, fileName);

      // 4. Iniciar Worker
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Creando Backup...');
      
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _zipWorker, 
        _ZipWorkerArgs(
          zipPath: zipFilePath, 
          entries: filesToZip, 
          sendPort: receivePort.sendPort
        ),
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
      );

      // 5. Escuchar progreso
      await _listenWorker(receivePort, 'Comprimiendo...');

      AppData.backgroundTaskProgress.value = null;

      // 6. Exportar
      await Share.shareXFiles([XFile(zipFilePath)], text: 'Backup de Atril Digital');

    } catch (e) {
      debugPrint('Error creando backup: $e');
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (dbSnapshot != null) {
        try { if (await dbSnapshot.exists()) await dbSnapshot.delete(); } catch (_) {}
      }
    }
  }

  /// Escucha un worker de zip/unzip hasta 'DONE'. Lanza si informa un error
  /// o si el isolate muere sin avisar (onError/onExit).
  Future<void> _listenWorker(ReceivePort port, String label) async {
    try {
      await for (final message in port) {
        if (message is double) {
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(message, label);
        } else if (message == 'DONE') {
          return;
        } else if (message is String && message.startsWith('ERROR:')) {
          throw Exception(message);
        } else if (message == null) {
          throw Exception('El proceso de compresión terminó inesperadamente.');
        } else if (message is List) {
          throw Exception('Error en el proceso de compresión: ${message.first}');
        }
      }
    } finally {
      port.close();
    }
  }

  /// Restaura un archivo .atril reemplazando la biblioteca actual.
  ///
  /// Es destructivo por diseño, pero seguro ante fallas:
  /// 1. Extrae y VALIDA el backup (integridad SQLite + que se pueda leer)
  ///    antes de tocar nada.
  /// 2. Mueve la DB y los PDFs actuales a una copia de resguardo (`*.restore_bak`).
  /// 3. Instala lo nuevo y reabre la DB.
  /// 4. Si cualquier paso falla, vuelve a poner la biblioteca anterior.
  /// En todos los casos la DB queda abierta al terminar. Lanza si falla.
  Future<void> restoreBackup(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(appDir.path, 'atril.sqlite'));
    final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));
    final sidecars = [
      File(p.join(appDir.path, 'atril.sqlite-wal')),
      File(p.join(appDir.path, 'atril.sqlite-shm')),
    ];

    const bakSuffix = '.restore_bak';
    final dbBak = File('${dbFile.path}$bakSuffix');
    final docsBak = Directory('${docsDir.path}$bakSuffix');

    // 1. Unzip en Isolate (Evita OOM)
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Verificando y extrayendo backup...');
    
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(p.join(tempDir.path, 'restore_extraction_${DateTime.now().millisecondsSinceEpoch}'));
    await extractDir.create(recursive: true);

    try {
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _unzipWorker, 
        _UnzipWorkerArgs(zipPath: sourcePath, destPath: extractDir.path, sendPort: receivePort.sendPort),
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
      );
      await _listenWorker(receivePort, 'Descomprimiendo para restaurar...');

      // 2. Validar ANTES de tocar la biblioteca actual
      final dbExtracted = File(p.join(extractDir.path, 'atril.sqlite'));
      if (!await dbExtracted.exists()) {
        throw Exception("El archivo no es un backup válido de Atril (falta la base de datos).");
      }
      await _validateBackupDb(dbExtracted);

      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Restaurando archivos...');

      // 3. Cerrar DB actual y resguardar lo actual
      await AppData.closeDbForRestore();

      var installed = false;
      try {
        // Limpiar resguardos viejos de un intento anterior
        if (await dbBak.exists()) await dbBak.delete();
        if (await docsBak.exists()) await docsBak.delete(recursive: true);
        for (final s in sidecars) {
          final b = File('${s.path}$bakSuffix');
          if (await b.exists()) await b.delete();
        }

        if (await dbFile.exists()) await dbFile.rename(dbBak.path);
        for (final s in sidecars) {
          if (await s.exists()) await s.rename('${s.path}$bakSuffix');
        }
        if (await docsDir.exists()) await docsDir.rename(docsBak.path);

        // 4. Instalar lo nuevo
        await dbExtracted.copy(dbFile.path);
        final docsExtracted = Directory(p.join(extractDir.path, 'docs'));
        if (await docsExtracted.exists()) {
          await _moveDir(docsExtracted, docsDir);
        } else {
          await docsDir.create(recursive: true);
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
        if (await dbBak.exists()) await dbBak.delete();
        if (await docsBak.exists()) await docsBak.delete(recursive: true);
        for (final s in sidecars) {
          final b = File('${s.path}$bakSuffix');
          if (await b.exists()) await b.delete();
        }
      } catch (e) {
        debugPrint('Warning: no se pudieron borrar los resguardos del restore: $e');
      }
      await PageEditRepository.discardAllUndo();
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (await extractDir.exists()) {
        try { await extractDir.delete(recursive: true); } catch (_) {}
      }
    }
  }

  /// Abre la DB del backup en modo aislado y verifica que esté sana.
  Future<void> _validateBackupDb(File dbFile) async {
    final candidate = AppDatabase(executor: NativeDatabase(dbFile));
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
    File dbFile,
    Directory docsDir,
    List<File> sidecars,
    File dbBak,
    Directory docsBak,
    String bakSuffix,
  ) async {
    try {
      if (await dbBak.exists()) {
        if (await dbFile.exists()) await dbFile.delete();
        await dbBak.rename(dbFile.path);
      }
      for (final s in sidecars) {
        final b = File('${s.path}$bakSuffix');
        if (await b.exists()) {
          if (await s.exists()) await s.delete();
          await b.rename(s.path);
        }
      }
      if (await docsBak.exists()) {
        if (await docsDir.exists()) await docsDir.delete(recursive: true);
        await docsBak.rename(docsDir.path);
      }
    } catch (e) {
      // Si llegamos acá, los resguardos siguen en disco (*.restore_bak).
      debugPrint('ERROR CRÍTICO en rollback del restore: $e');
    }
  }

  /// Mueve un directorio (rename; si falla, copia recursiva).
  Future<void> _moveDir(Directory from, Directory to) async {
    try {
      await from.rename(to.path);
    } catch (e) {
      debugPrint("Rename failed, copying: $e");
      await to.create(recursive: true);
      await for (final entity in from.list(recursive: true)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: from.path);
          final dest = File(p.join(to.path, rel));
          await dest.parent.create(recursive: true);
          await entity.copy(dest.path);
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
  Future<ImportBackupReport> importBackup(String sourcePath) async {
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(p.join(tempDir.path, 'import_extraction_${DateTime.now().millisecondsSinceEpoch}'));
    final copiedFiles = <File>[];

    try {
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Preparando importación...');
      await extractDir.create(recursive: true);

      // 1. Unzip en Isolate (Evita OOM)
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _unzipWorker,
        _UnzipWorkerArgs(zipPath: sourcePath, destPath: extractDir.path, sendPort: receivePort.sendPort),
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
      );
      await _listenWorker(receivePort, 'Descomprimiendo backup...');

      // 2. Abrir y validar la DB del backup
      final dbFile = File(p.join(extractDir.path, 'atril.sqlite'));
      if (!await dbFile.exists()) throw Exception("Backup inválido (falta la base de datos).");
      await _validateBackupDb(dbFile);

      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Procesando datos...');

      final externalDb = AppDatabase(executor: NativeDatabase(dbFile));
      try {
        final extFolders = await externalDb.getAllFolders();
        final extDocs = await externalDb.getAllDocs();
        final extStrokes = await externalDb.getAllAnnotationStrokes();
        final extSetlists = await externalDb.getAllSetlists();
        final extItems = await externalDb.getAllSetlistItemsOrdered();

        final docsDir = await AppData.storage.getDocsDir();
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        final rootImportId = AppData.newFolderId();

        // 3. Copiar PDFs primero (fuera de la transacción). Se registra cada
        //    copia para poder borrarla si la transacción falla.
        final docIdMap = <String, String>{}; // id en backup -> id nuevo
        final newRelPath = <String, String>{};
        var missingFiles = 0;
        for (var i = 0; i < extDocs.length; i++) {
          final d = extDocs[i];
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
            (i + 1) / extDocs.length, 'Copiando PDFs (${i + 1}/${extDocs.length})...');

          final source = await _findBackupPdf(extractDir, d.internalRelPath);
          if (source == null) {
            missingFiles++;
            debugPrint("Advertencia: PDF no encontrado en el backup para '${d.displayName}'");
            continue;
          }
          final newDocId = AppData.newDocId();
          final newFilename = '$newDocId.pdf';
          final dest = File(p.join(docsDir.path, newFilename));
          await source.copy(dest.path);
          copiedFiles.add(dest);
          docIdMap[d.id] = newDocId;
          newRelPath[d.id] = p.join('docs', newFilename);
        }

        // 4. Escrituras de DB en una sola transacción
        AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Guardando en la biblioteca...');
        var annotations = 0;
        var setlists = 0;
        await AppData.db.transaction(() async {
          await AppData.db.createFolder(
            id: rootImportId,
            name: "Backup Importado ($dateStr)",
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
        try { if (await f.exists()) await f.delete(); } catch (_) {}
      }
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (await extractDir.exists()) {
        try { await extractDir.delete(recursive: true); } catch (_) {}
      }
    }
  }

  /// Busca el PDF de un doc dentro del backup extraído (ruta guardada o
  /// fallback a docs/<basename>). Nunca sale del directorio extraído.
  Future<File?> _findBackupPdf(Directory extractDir, String internalRelPath) async {
    final root = p.normalize(p.absolute(extractDir.path));
    final rel = internalRelPath.replaceAll('\\', '/');
    final candidates = [
      p.normalize(p.join(root, rel)),
      p.normalize(p.join(root, 'docs', p.basename(rel))),
    ];
    for (final c in candidates) {
      if (!p.isWithin(root, c)) continue;
      final f = File(c);
      if (await f.exists()) return f;
    }
    return null;
  }

  /// Exporta la biblioteca como un ZIP legible para PC.
  ///
  /// Si [includeAnnotations] es 	rue, los PDFs con anotaciones se exportan
  /// con las anotaciones aplicadas (copias temporales; los originales no se
  /// modifican).
  Future<void> exportLibraryToZip(BuildContext context, {bool includeAnnotations = false}) async {
    Directory? workDir;
    try {
      // 1. Preparar destino
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'Biblioteca_Atril_$timestamp.zip';
      final tempDir = await getTemporaryDirectory();
      final zipFilePath = p.join(tempDir.path, fileName);
      
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
        final file = File(score.filePath!);
        if (!await file.exists()) continue;

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

      // 3. Iniciar Worker
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Exportando...');
      
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _zipWorker, 
        _ZipWorkerArgs(
          zipPath: zipFilePath, 
          entries: filesToZip, 
          sendPort: receivePort.sendPort
        )
      );

      // 4. Escuchar progreso
      await for (final message in receivePort) {
        if (message is double) {
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(message, 'Exportando a PC...');
        } else if (message == 'DONE') {
           break;
        } else if (message is String && message.startsWith('ERROR:')) {
           throw Exception(message);
        }
      }

      AppData.backgroundTaskProgress.value = null;
      await ExportManager.instance.deleteDirQuietly(workDir);

      // 5. Share
      await Share.shareXFiles([XFile(zipFilePath)], text: 'Exportación de Biblioteca Atril');

    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error exportando biblioteca: $e');
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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

// --- ISOLATE WORKER HELPERS ---

class _BackupFileEntry {
  /// Mutable: se reemplaza por la copia aplanada al incluir anotaciones.
  String sourcePath;
  final String zipPath;
  _BackupFileEntry(this.sourcePath, this.zipPath);
}

class _ZipWorkerArgs {
  final String zipPath;
  final List<_BackupFileEntry> entries;
  final SendPort sendPort;
  _ZipWorkerArgs({required this.zipPath, required this.entries, required this.sendPort});
}

Future<void> _zipWorker(_ZipWorkerArgs args) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(args.zipPath);

    int count = 0;
    final total = args.entries.length;

    for (final entry in args.entries) {
      final file = File(entry.sourcePath);
      if (await file.exists()) {
        await encoder.addFile(file, entry.zipPath);
      }
      count++;
      // Reportar progreso
      args.sendPort.send(count / total);
    }

    encoder.close();
    args.sendPort.send('DONE');
  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}

class _UnzipWorkerArgs {
  final String zipPath;
  final String destPath;
  final SendPort sendPort;
  _UnzipWorkerArgs({required this.zipPath, required this.destPath, required this.sendPort});
}

Future<void> _unzipWorker(_UnzipWorkerArgs args) async {
  try {
    // Usamos InputFileStream para evitar cargar todo el zip a memoria
    final inputStream = InputFileStream(args.zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);

    final totalFiles = archive.length; 
    int count = 0;
    
    for (final file in archive) {
      if (file.isFile) {
         // Protección zip-slip: ninguna entrada puede escribir fuera del destino.
         final root = p.normalize(p.absolute(args.destPath));
         final destPath = p.normalize(p.join(root, file.name));
         if (!p.isWithin(root, destPath)) {
           count++;
           continue;
         }
         // Asegurar que el directorio padre existe
         final parentDir = Directory(p.dirname(destPath));
         if (!await parentDir.exists()) {
           await parentDir.create(recursive: true);
         }
         
         final outputStream = OutputFileStream(destPath);
         file.writeContent(outputStream);
         outputStream.close();
      }
      count++;
      if (count % 10 == 0) { 
         args.sendPort.send(count / totalFiles);
      }
    }
    
    inputStream.close();
    args.sendPort.send('DONE');

  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}
