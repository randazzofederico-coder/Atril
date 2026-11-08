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

  Future<void> importBackup(BuildContext context, String sourcePath) async {
    try {
       AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Preparando Importación...');

       // 1. Unzip en Isolate (Evita OOM)
       final tempDir = await getTemporaryDirectory();
       final extractDirName = 'import_extraction_${DateTime.now().millisecondsSinceEpoch}';
       final extractDir = Directory(p.join(tempDir.path, extractDirName));
       await extractDir.create(recursive: true);

       final receivePort = ReceivePort();
       await Isolate.spawn(
          _unzipWorker, 
          _UnzipWorkerArgs(
            zipPath: sourcePath, 
            destPath: extractDir.path, 
            sendPort: receivePort.sendPort
          )
       );

       await for (final message in receivePort) {
          if (message is double) {
             AppData.backgroundTaskProgress.value = BackgroundTaskStatus(message, 'Descomprimiendo backup...');
          } else if (message == 'DONE') {
             break;
          } else if (message is String && message.startsWith('ERROR:')) {
             throw Exception(message);
          }
       }
       
       AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Procesando datos...');

       // 2. Open External DB
       final dbPath = p.join(extractDir.path, 'atril.sqlite');
       if (!await File(dbPath).exists()) throw Exception("Backup inválido (falta DB).");
       
       final externalDb = AppDatabase(executor: NativeDatabase(File(dbPath)));

       try {
        // 3. Crear Carpeta Raíz de Importación
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        final rootImportId = AppData.newFolderId();
        await AppData.db.createFolder(
          id: rootImportId,
          name: "Backup Importado ($dateStr)",
          parentId: null, // Raíz
          position: 999, // Al final
        );

        // 4. Leer todo del backup
        final extFolders = await externalDb.getAllFolders();
        final extDocs = await externalDb.getAllDocs();
        
        final idMap = <String, String>{};
        idMap['root'] = rootImportId;
        
        // 5. Migrar Carpetas
        for (final f in extFolders) {
          if (f.id == 'root') continue;
          
          final newId = AppData.newFolderId();
          idMap[f.id] = newId;

          await AppData.db.createFolder(
            id: newId,
            name: f.name,
            parentId: rootImportId,
            position: f.position,
            isDeleted: f.isDeleted,
            deletedAt: f.deletedAt,
          );
        }

        for (final f in extFolders) {
            if (f.id == 'root') continue;

            String? targetParentId;
            if (f.parentId == null) {
              targetParentId = rootImportId;
            } else {
              targetParentId = idMap[f.parentId];
              targetParentId ??= rootImportId;
            }

            if (targetParentId != rootImportId) {
               final newId = idMap[f.id]!;
               await AppData.db.upsertFolder(
                 id: newId,
                 name: f.name,
                 parentId: targetParentId,
                 position: f.position,
                 isDeleted: f.isDeleted,
                 deletedAt: f.deletedAt,
               );
            }
        }

        // 6. Migrar Documentos
        final docsDir = await AppData.storage.getDocsDir();
        
        int docCount = 0;
        final totalDocs = extDocs.length;
        final docIdMap = <String, String>{}; // id en backup -> id nuevo

        for (final d in extDocs) {
          docCount++;
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(docCount / totalDocs, 'Importando PDFs ($docCount/$totalDocs)...');
          
          final newDocId = AppData.newDocId();
          
          // Debug Path Construction
          var internalPath = d.internalRelPath;
          // Sanitizar separadores por si acaso vienen de Windows
          internalPath = internalPath.replaceAll('\\', '/');
          
          var backupFile = File(p.join(extractDir.path, internalPath));
          
          if (!await backupFile.exists()) {
             // Fallback: Check inside 'docs' folder explicitly
             final retryFile = File(p.join(extractDir.path, 'docs', p.basename(internalPath)));
             if (await retryFile.exists()) {
                debugPrint("Info: Archivo encontrado en subcarpeta docs/ (Fallback): ${retryFile.path}");
                backupFile = retryFile;
             } else {
                debugPrint("Warning: PDF NO ENCONTRADO. Buscado en:\n 1. ${backupFile.path}\n 2. ${retryFile.path}");
             }
          }
          
          if (await backupFile.exists()) {
             final newFilename = '$newDocId.pdf';
             final destFile = File(p.join(docsDir.path, newFilename));
             
             await backupFile.copy(destFile.path);
             docIdMap[d.id] = newDocId;

             String? newFolderId = rootImportId;
             if (d.folderId != null) {
               newFolderId = idMap[d.folderId] ?? rootImportId;
             }

             await AppData.db.upsertDoc(
               id: newDocId,
               displayName: d.displayName,
               author: d.author ?? '',
               internalRelPath: p.join('docs', newFilename), // Corregido: Debe incluir 'docs/'
               folderId: newFolderId,
               isDeleted: d.isDeleted,
               deletedAt: d.deletedAt,
             );
          } else {
            debugPrint("Advertencia: Archivo PDF no encontrado irrecuperable para doc ${d.displayName}");
          }
        }
        
        // 7. Migrar anotaciones de los documentos importados
        try {
          final extStrokes = await externalDb.getAllAnnotationStrokes();
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
          }
        } catch (e) {
          debugPrint("Warning: no se pudieron migrar anotaciones del backup: $e");
        }

        await AppData.refreshLibrary();
        debugPrint("Importación finalizada con éxito.");

      } finally {
        await externalDb.close();
      }
       
       AppData.backgroundTaskProgress.value = null;

    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint("Error importing backup: $e");
       if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
        final tempDir = await getTemporaryDirectory();
        try {
           final list = tempDir.listSync();
           for (final f in list) {
             if (f is Directory && p.basename(f.path).startsWith('import_extraction_')) {
               try { await f.delete(recursive: true); } catch(_) {}
             }
           }
        } catch (_) {}
    }
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
