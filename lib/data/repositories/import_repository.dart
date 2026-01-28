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
    // Global UI
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Iniciando importación...');

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
        // Global UI
        AppData.backgroundTaskProgress.value = BackgroundTaskStatus(current / total, 'Importando $fileName');

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
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Finalizando importación...');
    
    await AppData.refreshLibrary();

    // Reset a estado inactivo
    _updateState(stage: ImportStage.idle);
    AppData.backgroundTaskProgress.value = null;
  }

  /// Importa una carpeta recursivamente en background con reporte de progreso global.
  static Future<void> importFolderBackground(String path, String targetParentId) async {
    // 1. Pre-cálculo para porcentaje real
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Analizando carpeta...');
    int totalFiles = 0;
    try {
      totalFiles = await _countPdfFiles(path);
    } catch (e) {
      debugPrint("Error contando archivos: $e");
    }

    if (totalFiles == 0) {
      AppData.backgroundTaskProgress.value = null;
      return;
    }

    // 2. Importación recursiva
    _updateState(stage: ImportStage.processing, total: totalFiles, current: 0);
    
    // Wrapper class to pass integer by reference
    final counter = _Counter();
    
    await _importFolderRecursiveBackground(path, targetParentId, totalFiles, counter);

    // 3. Finalización
    AppData.backgroundTaskProgress.value = const BackgroundTaskStatus(1.0, 'Finalizando importación...');
    await AppData.refreshLibrary();
    
    _updateState(stage: ImportStage.idle);
    AppData.backgroundTaskProgress.value = null;
  }

  static Future<int> _countPdfFiles(String path) async {
    int count = 0;
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    
    final entities = dir.listSync(recursive: true); // Recursive list is faster for counting
    for (final entity in entities) {
       if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
         count++;
       }
    }
    return count;
  }

  static Future<void> _importFolderRecursiveBackground(
    String path, 
    String targetParentId, 
    int totalFiles,
    _Counter counter
  ) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    final folderName = p.basename(dir.path);
    
    // Crear carpeta (si no es la raíz del import, aunque la UX manda el path seleccionado)
    // En la lógica original, creaba carpeta con el nombre de la carpeta seleccionada.
    final newFolderId = await AppData.createFolder(
       name: folderName,
       parentId: targetParentId,
       refresh: false,
    );

    try {
      final entities = dir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
           final fileName = p.basename(entity.path).replaceAll('.pdf', '');
           
           counter.val++;
           AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
             counter.val / totalFiles, 
             'Importando $fileName (${counter.val}/$totalFiles)...'
           );

           try {
             await importPdfFromExternalPath(
                sourcePath: entity.path,
                desiredTitle: fileName,
                targetFolderId: newFolderId,
                refresh: false
             );
           } catch (e) {
             debugPrint("Error importando $fileName: $e");
           }
           
           // Yield to UI
           await Future.delayed(Duration.zero);
           
        } else if (entity is Directory) {
           final name = p.basename(entity.path);
           if (!name.startsWith('.')) {
             await _importFolderRecursiveBackground(entity.path, newFolderId, totalFiles, counter);
           }
        }
      }
    } catch (e) {
      debugPrint("Error procesando carpeta $path: $e");
    }
  }
}

class _Counter {
  int val = 0;
}