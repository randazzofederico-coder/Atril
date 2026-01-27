import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// Eliminado: import 'package:file_picker/file_picker.dart'; 

import 'app_data.dart';
import 'app_database.dart';

class BackupManager {
  BackupManager._();

  static final BackupManager instance = BackupManager._();

  /// Genera un archivo .atril (ZIP) con la DB y los PDFs y lanza el diálogo de compartir/guardar.
  Future<void> createBackup() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(appDir.path, 'atril.sqlite'));
      final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));

      // 1. Preparar Encoder
      final archive = Archive();

      // 2. Agregar DB
      if (await dbFile.exists()) {
        final dbBytes = await dbFile.readAsBytes();
        archive.addFile(ArchiveFile('atril.sqlite', dbBytes.lengthInBytes, dbBytes));
      } else {
        throw Exception("No se encontró la base de datos.");
      }

      // 3. Agregar PDFs
      if (await docsDir.exists()) {
        final files = docsDir.listSync(recursive: true);
        for (final file in files) {
          if (file is File) {
            final filename = p.relative(file.path, from: docsDir.path);
            final bytes = await file.readAsBytes();
            archive.addFile(ArchiveFile('docs/$filename', bytes.lengthInBytes, bytes));
          }
        }
      }

      // 4. Comprimir
      final zipEncoder = ZipEncoder();
      final encodedZip = zipEncoder.encode(archive);

      if (encodedZip == null) throw Exception("Error codificando el backup.");

      // 5. Guardar archivo temporal
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'backup_atril_$timestamp.atril';
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, fileName));
      
      await tempFile.writeAsBytes(encodedZip);

      // 6. Exportar
      await Share.shareXFiles([XFile(tempFile.path)], text: 'Backup de Atril Digital');

    } catch (e) {
      debugPrint('Error creando backup: $e');
      rethrow;
    }
  }

  /// Restaura un archivo .atril reemplazando la data actual.
  /// ¡DESTRUCTIVO!
  Future<void> restoreBackup(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(appDir.path, 'atril.sqlite'));
    final docsDir = Directory(p.join(appDir.path, 'atril', 'docs'));
    final shmFile = File(p.join(appDir.path, 'atril.sqlite-shm'));
    final walFile = File(p.join(appDir.path, 'atril.sqlite-wal'));

    // 1. Validar ZIP
    final bytes = await File(sourcePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    bool hasDb = archive.any((f) => f.name == 'atril.sqlite');
    if (!hasDb) throw Exception("El archivo no es un backup válido de Atril (falta DB).");

    // 2. CERRAR DB ACTUAL (Crítico)
    await AppData.closeDbForRestore();

    try {
      // 3. Limpiar estado actual (Wipe)
      if (await dbFile.exists()) await dbFile.delete();
      if (await shmFile.exists()) await shmFile.delete();
      if (await walFile.exists()) await walFile.delete();
      
      if (await docsDir.exists()) {
        await docsDir.delete(recursive: true);
      }
      await docsDir.create(recursive: true);

      // 4. Extraer
      for (final file in archive) {
        if (file.isFile) {
          if (file.name == 'atril.sqlite') {
            await dbFile.writeAsBytes(file.content as List<int>);
          } else if (file.name.startsWith('docs/')) {
            final relPath = file.name.replaceFirst('docs/', '');
            if (relPath.isEmpty) continue;
            
            final destFile = File(p.join(docsDir.path, relPath));
            await destFile.create(recursive: true);
            await destFile.writeAsBytes(file.content as List<int>);
          }
        }
      }

      // 5. Reinicializar
      await AppData.init(forceReopen: true);

    } catch (e) {
      debugPrint("Error fatal en restore: $e");
      rethrow;
    }
  }


  Future<void> importBackup(String sourcePath) async {
    // 1. Unzip to temp location
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(p.join(tempDir.path, 'import_extraction_${DateTime.now().millisecondsSinceEpoch}'));
    await extractDir.create(recursive: true);

    try {
      final bytes = await File(sourcePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      bool hasDb = archive.any((f) => f.name == 'atril.sqlite');
      if (!hasDb) throw Exception("Backup inválido (falta DB).");

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
         final data = file.content as List<int>;
         final outFile = File(p.join(extractDir.path, filename));
         await outFile.create(recursive: true);
         await outFile.writeAsBytes(data);
        }
      }

      // 2. Open External DB
      final dbPath = p.join(extractDir.path, 'atril.sqlite');
      final externalDb = AppDatabase(customFile: File(dbPath));

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
        
        // Mapa: Old ID -> New ID
        final idMap = <String, String>{};
        idMap['root'] = rootImportId; // Map backup 'root' to our container folder
        
        // 5. Migrar Carpetas (Two-Pass para evitar FK Constraints)
        
        // Pass 1: Insertar todas con parentId = rootImportId (Safe Parent)
        for (final f in extFolders) {
          if (f.id == 'root') continue; // Skip creating 'root' again, we use rootImportId
          
          final newId = AppData.newFolderId();
          idMap[f.id] = newId;

          await AppData.db.createFolder(
            id: newId,
            name: f.name,
            parentId: rootImportId, // Temporalmente todas cuelgan del Root de Importación
            position: f.position,
          );
        }

        // Pass 2: Actualizar parentId correcto
        // Ahora que todas existen, podemos linkearlas.
        for (final f in extFolders) {
            if (f.id == 'root') continue; // Skip root

            String? targetParentId;
            if (f.parentId == null) {
              targetParentId = rootImportId;
            } else {
              targetParentId = idMap[f.parentId];
              targetParentId ??= rootImportId; // Fallback
            }

            // Solo hacemos update si el parent NO es rootImportId (ya que así nacieron)
            if (targetParentId != rootImportId) {
               // Usamos renameFolder para moverla? No, renameFolder es lógica de negocio.
               // Usamos moveItems? También lógica de negocio.
               // Usemos Direct DB Update.
               // AppData.db.upsertFolder sirve para UPDATE también.
               // Re-insertamos con el ID existente y el nuevo Parent.
               final newId = idMap[f.id]!;
               await AppData.db.upsertFolder(
                 id: newId,
                 name: f.name,
                 parentId: targetParentId,
                 position: f.position,
               );
            }
        }

        // 6. Migrar Documentos y Archivos
        final docsDir = await AppData.storage.getDocsDir();
        
        for (final d in extDocs) {
          final newDocId = AppData.newDocId();
          // Copiar archivo físico
          // La ruta interna en el backup: d.internalRelPath (ej: "docs/uuid.pdf")
          // El zip se extrajo tal cual, asi que en disco está en extractDir/docs/uuid.pdf
          final backupFile = File(p.join(extractDir.path, d.internalRelPath));
          
          if (await backupFile.exists()) {
             // Destino
             final newFilename = '$newDocId.pdf';
             final destFile = File(p.join(docsDir.path, newFilename));
             await backupFile.copy(destFile.path);

             // Insertar Doc
             String? newFolderId = rootImportId;
             if (d.folderId != null) {
               newFolderId = idMap[d.folderId] ?? rootImportId;
             }

             await AppData.db.upsertDoc(
               id: newDocId,
               displayName: d.displayName,
               author: d.author ?? '',
               internalRelPath: newFilename, // IMPORTANTE: Nueva ruta física
               folderId: newFolderId,
             );
          } else {
            debugPrint("Advertencia: Archivo PDF no encontrado en backup para doc ${d.displayName} (${d.internalRelPath})");
          }
        }
        
        await AppData.refreshLibrary();
        debugPrint("Importación finalizada con éxito.");

      } finally {
        await externalDb.close();
      }
       
    } catch (e) {
      debugPrint("Error importing backup: $e");
      rethrow;
    } finally {
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
    }
  }

  /// Exporta la biblioteca como un ZIP legible para PC.
  /// Reconstruye la estructura de carpetas y renombra los archivos a su Título.
  Future<void> exportLibraryToZip() async {
    try {
      final archive = Archive();

      // Helper para obtener el path completo de un folder
      String getFolderPath(String? folderId) {
        if (folderId == null) return '';
        final f = AppData.getFolderById(folderId);
        if (f == null) return '';
        final parentPath = getFolderPath(f.parentId);
        final safeName = _sanitizeFilename(f.name);
        return parentPath.isEmpty ? safeName : '$parentPath/$safeName';
      }



      // Recorrer todos los Docs
      for (final score in AppData.library) {
        if (score.filePath == null) continue;
        final file = File(score.filePath!);
        if (!await file.exists()) continue;

        // 1. Construir ruta virtual
        final folderPath = getFolderPath(score.folderId);
        final safeTitle = _sanitizeFilename(score.title);
        
        // 2. Construir ruta dentro del ZIP
        // Si hay conflicto de nombres, se podría manejar, pero por ahora asumimos que el usuario cuida sus nombres.
        // Ojo: Appendemos .pdf si no lo tiene.
        var filename = safeTitle;
        if (!filename.toLowerCase().endsWith('.pdf')) {
          filename += '.pdf';
        }

        final zipPath = folderPath.isEmpty ? filename : '$folderPath/$filename';

        // 3. Agregar al archivo
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(zipPath, bytes.lengthInBytes, bytes));
      }

      // 4. Comprimir
      final zipEncoder = ZipEncoder();
      final encodedZip = zipEncoder.encode(archive);
      if (encodedZip == null) throw Exception("Error codificando exportación.");

      // 5. Guardar temporalmente
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'Biblioteca_Atril_$timestamp.zip';
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, fileName));
      await tempFile.writeAsBytes(encodedZip);

      // 6. Share
      await Share.shareXFiles([XFile(tempFile.path)], text: 'Exportación de Biblioteca Atril');

    } catch (e) {
      debugPrint('Error exportando biblioteca: $e');
      rethrow;
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}