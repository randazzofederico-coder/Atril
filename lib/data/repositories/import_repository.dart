import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../models/score.dart';
import '../app_data.dart';
// Eliminado: import 'library_repository.dart'; <- Ya viene incluido dentro de app_data.dart

// --- CLASES Y ENUMS ---

/// Define las fases de la importación para la UI
enum ImportStage { idle, picking, processing, finishing }

/// Estado para notificar a la barra de progreso
class ImportState {
  final ImportStage stage;
  final int total;
  final int current;
  final String currentItemName;

  const ImportState({
    this.stage = ImportStage.idle,
    this.total = 0,
    this.current = 0,
    this.currentItemName = '',
  });

  bool get isActive => stage != ImportStage.idle;

  double? get progress => (total > 0 && stage == ImportStage.processing)
      ? current / total
      : null;
}

/// DTO legacy para reportar el progreso
class ImportStatus {
  final int count;
  final String currentFile;
  final bool completed;

  const ImportStatus({
    required this.count,
    required this.currentFile,
    this.completed = false,
  });
}

// --- CLASE REPOSITORIO ---

class ImportRepository {
  
  // Helpers privados para actualizar el estado en AppData
  static void _updateState({
    required ImportStage stage,
    int total = 0,
    int current = 0,
    String name = '',
  }) {
    AppData.importState.value = ImportState(
      stage: stage,
      total: total,
      current: current,
      currentItemName: name,
    );
  }

  /// Lógica CORE movida desde AppData.
  /// Importa un único PDF desde una ruta externa al almacenamiento interno y DB.
  static Future<Score> importPdfFromExternalPath({
    required String sourcePath,
    required String desiredTitle,
    String author = '',
    String targetFolderId = 'root',
    bool refresh = true,
  }) async {
    // 1. Validar unicidad de título (Logica de Negocio)
    // Accedemos a LibraryRepository a través del export de AppData
    final title = LibraryRepository.uniqueTitle(desiredTitle);
    
    // 2. Generar ID y Persistir archivo (Logica de Storage)
    final docId = AppData.newDocId();
    final relPath = await AppData.storage.importPdfFromExternalPath(
      sourcePath: sourcePath,
      docId: docId,
    );

    // 3. Guardar en Base de Datos (Logica de DB)
    await AppData.db.upsertDoc(
      id: docId,
      displayName: title,
      author: author,
      internalRelPath: relPath,
      folderId: targetFolderId,
    );

    // 4. Actualizar Estado (State Management)
    if (refresh) await AppData.refreshLibrary();
    
    // Si no refrescamos (ej: batch import), devolvemos el objeto construido manualmente
    if (!refresh) {
       return Score(
         docId: docId, 
         title: title, 
         author: author, 
         filePath: AppData.storage.absPathFromRelPath(relPath), 
         folderId: targetFolderId
       );
    }
    
    // Si refrescamos, lo buscamos en el cache actualizado
    return AppData.getScoreById(docId)!;
  }

  /// Procesa una lista de rutas sin bloquear y actualiza AppData.importState.
  static Future<void> importBatchBackground(List<String> filePaths, String targetFolderId) async {
    final total = filePaths.length;
    int current = 0;

    // Estado inicial: Procesando 0/Total
    _updateState(stage: ImportStage.processing, total: total, current: 0);

    for (final path in filePaths) {
      try {
        final fileName = p.basename(path).replaceAll('.pdf', '');
        
        // Actualizamos UI: Procesando nombre...
        _updateState(
          stage: ImportStage.processing,
          total: total,
          current: current + 1,
          name: fileName,
        );

        await importPdfFromExternalPath(
          sourcePath: path,
          desiredTitle: fileName,
          targetFolderId: targetFolderId,
          refresh: false, // No refrescamos la UI entera por cada archivo
        );

        current++;
        // Delay mínimo para no bloquear el UI thread
        await Future.delayed(Duration.zero);
      } catch (e) {
        debugPrint("Error importando $path: $e");
      }
    }

    // Refrescar DB y UI global
    _updateState(stage: ImportStage.finishing, name: 'Actualizando biblioteca...');
    await AppData.refreshLibrary();

    // Reset a estado inactivo
    _updateState(stage: ImportStage.idle);
  }

  /// Método Stream para ImportProgressDialog
  static Stream<ImportStatus> importBatchStream(List<String> filePaths, String targetFolderId) async* {
    int current = 0;
    for (final path in filePaths) {
      final fileName = p.basename(path).replaceAll('.pdf', '');
      yield ImportStatus(count: current, currentFile: fileName);

      try {
        await importPdfFromExternalPath(
          sourcePath: path,
          desiredTitle: fileName,
          targetFolderId: targetFolderId,
          refresh: false,
        );
        current++;
        await Future.delayed(Duration.zero);
      } catch (e) {
        debugPrint("Error importando $path: $e");
      }
      yield ImportStatus(count: current, currentFile: fileName);
    }

    // Refresco final
    await AppData.refreshLibrary();
    yield ImportStatus(count: current, currentFile: 'Finalizado', completed: true);
  }

  /// Método Recursivo (Legacy) para carpetas completas
  static Stream<ImportStatus> importFolderStream(String path, String targetParentId) async* {
    int totalImported = 0;
    await for (final count in _importFolderStreamRecursive(path, targetParentId)) {
      totalImported += count;
      yield ImportStatus(
        count: totalImported,
        currentFile: 'Procesando...',
      );
    }
    await AppData.refreshLibrary();
    yield ImportStatus(count: totalImported, currentFile: 'Finalizado', completed: true);
  }

  static Stream<int> _importFolderStreamRecursive(
    String path,
    String targetParentId,
  ) async* {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) return;
    } catch (e) {
      debugPrint("Error verificando directorio: $e");
      return;
    }

    final folderName = p.basename(dir.path);
    // Crea la carpeta lógica usando AppData
    final newFolderId = await AppData.createFolder(
      name: folderName,
      parentId: targetParentId,
      refresh: false,
    );

    try {
      final entities = dir.listSync(recursive: false);
      for (final entity in entities) {
        try {
          bool isFile = (entity is File);
          if (!isFile && FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.file) isFile = true;

          if (isFile) {
            if (entity.path.toLowerCase().endsWith('.pdf')) {
              final fileName = p.basename(entity.path).replaceAll('.pdf', '');
              
              await importPdfFromExternalPath(
                sourcePath: entity.path,
                desiredTitle: fileName,
                targetFolderId: newFolderId,
                refresh: false,
              );
              
              yield 1; // Contamos 1 archivo
              await Future.delayed(Duration.zero);
            }
          } else if (entity is Directory) {
            final name = p.basename(entity.path);
            if (!name.startsWith('.')) {
              yield* _importFolderStreamRecursive(entity.path, newFolderId);
            }
          }
        } catch (e) {
          debugPrint("Error importando ítem ${entity.path}: $e");
        }
      }
    } catch (e) {
      debugPrint("Error listando carpeta $path: $e");
    }
  }
}