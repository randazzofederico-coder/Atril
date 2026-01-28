import 'dart:io';
import 'dart:async';
import 'dart:isolate'; // Worker
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_data.dart';
import 'app_database.dart';

class BackupManager {
  BackupManager._();

  static final BackupManager instance = BackupManager._();

  /// Genera un archivo .atril (ZIP) con la DB y los PDFs y lanza el diálogo de compartir/guardar.
  Future<void> createBackup(BuildContext context) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(appDir.path, 'atril.sqlite'));
      final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));
      // 0. Feedback inmediato (con delay para render de UI)
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Escaneando biblioteca...');
      await Future.delayed(const Duration(milliseconds: 50));

      if (!await dbFile.exists()) throw Exception("No se encontró la base de datos.");

      // 1. Preparar lista de archivos
      final filesToZip = <_BackupFileEntry>[];
      filesToZip.add(_BackupFileEntry(dbFile.path, 'atril.sqlite'));

      if (await docsDir.exists()) {
        // Async list para no congelar UI
        final files = await docsDir.list(recursive: true).toList();
        for (final file in files) {
          if (file is File) {
            final filename = p.relative(file.path, from: docsDir.path);
            filesToZip.add(_BackupFileEntry(file.path, 'docs/$filename'));
          }
        }
      }

      // 2. Preparar destino
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'backup_atril_$timestamp.atril';
      final tempDir = await getTemporaryDirectory();
      final zipFilePath = p.join(tempDir.path, fileName);

      // 3. Iniciar Worker
      AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Creando Backup...');
      
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
          AppData.backgroundTaskProgress.value = BackgroundTaskStatus(message, 'Comprimiendo...');
        } else if (message == 'DONE') {
           break;
        } else if (message is String && message.startsWith('ERROR:')) {
           throw Exception(message);
        }
      }

      AppData.backgroundTaskProgress.value = null;

      // 5. Exportar
      await Share.shareXFiles([XFile(zipFilePath)], text: 'Backup de Atril Digital');

    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error creando backup: $e');
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Restaura un archivo .atril reemplazando la data actual.
  /// ¡DESTRUCTIVO!
  Future<void> restoreBackup(BuildContext context, String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(appDir.path, 'atril.sqlite'));
    final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));
    final shmFile = File(p.join(appDir.path, 'atril.sqlite-shm'));
    final walFile = File(p.join(appDir.path, 'atril.sqlite-wal'));

    // 1. Unzip en Isolate (Evita OOM)
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Verificando y extrayendo backup...');
    
    final tempDir = await getTemporaryDirectory();
    final extractDirName = 'restore_extraction_${DateTime.now().millisecondsSinceEpoch}';
    final extractDir = Directory(p.join(tempDir.path, extractDirName));
    await extractDir.create(recursive: true);

    try {
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
                AppData.backgroundTaskProgress.value = BackgroundTaskStatus(message, 'Descomprimiendo para restaurar...');
            } else if (message == 'DONE') {
                break;
            } else if (message is String && message.startsWith('ERROR:')) {
                throw Exception(message);
            }
        }
        
        // 2. Validar Contenido Extraído
        final dbExtractedPath = p.join(extractDir.path, 'atril.sqlite');
        if (!await File(dbExtractedPath).exists()) throw Exception("El archivo no es un backup válido de Atril (falta DB).");

        // 3. CERRAR DB ACTUAL (Crítico)
        await AppData.closeDbForRestore();
        
        AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Restaurando archivos...');

        // 4. Limpiar estado actual (Wipe)
        if (await dbFile.exists()) await dbFile.delete();
        if (await shmFile.exists()) await shmFile.delete();
        if (await walFile.exists()) await walFile.delete();
        
        if (await docsDir.exists()) {
            await docsDir.delete(recursive: true);
        }
        await docsDir.create(recursive: true);

        // 5. Mover archivos extraídos a destino final
        // Mover DB
        await File(dbExtractedPath).copy(dbFile.path);

        // Mover Docs
        final docsExtractedDir = Directory(p.join(extractDir.path, 'docs'));
        if (await docsExtractedDir.exists()) {
            try {
               await docsDir.delete();
               await docsExtractedDir.rename(docsDir.path);
            } catch (e) {
               // Fallback copy
               debugPrint("Rename failed, copying: $e");
               if (!await docsDir.exists()) await docsDir.create();
               final files = docsExtractedDir.listSync(recursive: true);
               for (final entity in files) {
                   if (entity is File) {
                       final rel = p.relative(entity.path, from: docsExtractedDir.path);
                       final dest = File(p.join(docsDir.path, rel));
                       await dest.create(recursive: true);
                       await entity.copy(dest.path);
                   }
               }
            }
        }

        // 6. Reinicializar
        AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Reiniciando base de datos...');
        await AppData.init(forceReopen: true);

    } catch (e) {
        debugPrint("Error fatal en restore: $e");
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
    } finally {
        AppData.backgroundTaskProgress.value = null;
        // Cleanup temp
        if (await extractDir.exists()) {
            await extractDir.delete(recursive: true);
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
               );
            }
        }

        // 6. Migrar Documentos
        final docsDir = await AppData.storage.getDocsDir();
        
        int docCount = 0;
        final totalDocs = extDocs.length;

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
             );
          } else {
            debugPrint("Advertencia: Archivo PDF no encontrado irrecuperable para doc ${d.displayName}");
          }
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
  Future<void> exportLibraryToZip(BuildContext context) async {
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

      for (final score in AppData.library) {
        if (score.filePath == null) continue;
        final file = File(score.filePath!);
        if (!await file.exists()) continue;

        final folderPath = getFolderPath(score.folderId);
        final safeTitle = _sanitizeFilename(score.title);
        
        var filename = safeTitle;
        if (!filename.toLowerCase().endsWith('.pdf')) {
           filename += '.pdf';
        }
        final zipPath = folderPath.isEmpty ? filename : '$folderPath/$filename';
        
        filesToZip.add(_BackupFileEntry(score.filePath!, zipPath));
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

      // 5. Share
      await Share.shareXFiles([XFile(zipFilePath)], text: 'Exportación de Biblioteca Atril');

    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error exportando biblioteca: $e');
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}

// --- ISOLATE WORKER HELPERS ---

class _BackupFileEntry {
  final String sourcePath;
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
         final destPath = p.join(args.destPath, file.name);
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