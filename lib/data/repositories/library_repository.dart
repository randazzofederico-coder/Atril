import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../models/score.dart';
import '../../models/folder.dart';
import '../app_data.dart';
import '../app_database.dart';
import 'page_edit_repository.dart';

class LibraryRepository {
  
  // ---------------------------------------------------------------------------
  // FOLDERS
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // FOLDERS
  // ---------------------------------------------------------------------------

  static Future<Folder> createFolder({
    required String name,
    required String parentId,
  }) async {
    // Garantizar nombre único (Auto-Rename)
    final uniqueName = uniqueFolderName(name, parentId);
    
    final id = AppData.newFolderId();
    // Calculamos posición basada en los folders actuales en memoria
    final siblings = AppData.folders.where((f) => (f.parentId ?? 'root') == parentId).length;
    
    // DB Update
    await AppData.db.createFolder(
      id: id,
      name: uniqueName,
      parentId: parentId == 'root' ? null : parentId,
      position: siblings,
    );

    // Return constructed object for local cache update
    return Folder(
      id: id, 
      name: uniqueName, 
      parentId: parentId, 
      position: siblings
    );
  }

  static bool folderNameExists(String name, String parentId) {
    return AppData.folders.any((f) => 
      (f.parentId ?? 'root') == parentId && 
      f.name.toLowerCase() == name.trim().toLowerCase()
    );
  }

  static String uniqueFolderName(String desiredName, String parentId) {
    final base = desiredName.trim();
    if (base.isEmpty) return 'Nueva Carpeta';

    if (!folderNameExists(base, parentId)) return base;

    var n = 2;
    while (true) {
      final cand = '$base ($n)';
      if (!folderNameExists(cand, parentId)) return cand;
      n++;
    }
  }

  static Future<Folder?> renameFolder(String folderId, String newName) async {
    final f = AppData.getFolderById(folderId);
    if (f == null) return null;

    // DB Update
    await AppData.db.upsertFolder(
      id: f.id,
      name: newName,
      parentId: f.parentId,
      position: f.position,
    );

    // Return updated object
    return Folder(
      id: f.id,
      name: newName,
      parentId: f.parentId,
      position: f.position,
    );
  }

  // ---------------------------------------------------------------------------
  // SCORES
  // ---------------------------------------------------------------------------

  static Future<Score?> updateScoreMetadata({
    required String docId, 
    required String newTitle, 
    required String newAuthor
  }) async {
    final s = AppData.getScoreById(docId);
    if (s == null) return null;
    
    final relPath = AppData.storage.docRelPath(s.docId);
    
    // DB Update
    await AppData.db.upsertDoc(
      id: s.docId,
      displayName: newTitle, 
      author: newAuthor,    
      internalRelPath: relPath,
      folderId: s.folderId,
    );

    return Score(
      docId: s.docId,
      title: newTitle,
      author: newAuthor,
      filePath: s.filePath,
      folderId: s.folderId,
    );
  }

  static Future<Score?> renameScore(String docId, String newTitle) async {
    return updateScoreMetadata(docId: docId, newTitle: newTitle, newAuthor: '');
  }

  static String uniqueTitle(String desiredTitle) {
    final base = desiredTitle.trim();
    if (base.isEmpty) return 'Sin Titulo';
    
    final exists = AppData.library.any((s) => s.title.toLowerCase() == base.toLowerCase());
    if (!exists) return base;
    
    var n = 2;
    while (true) {
      final cand = '$base ($n)';
      if (!AppData.library.any((s) => s.title.toLowerCase() == cand.toLowerCase())) return cand;
      n++;
    }
  }

  // ---------------------------------------------------------------------------
  // OPERACIONES EN LOTE (MOVIMIENTOS Y BORRADOS)
  // ---------------------------------------------------------------------------

  static Future<void> moveItems({
    required List<String> docIds,
    required List<String> folderIds,
    required String targetParentId,
  }) async {
    // 1. Mover Docs
    for (final docId in docIds) {
      final doc = AppData.getScoreById(docId);
      if (doc != null) {
        await AppData.db.upsertDoc(
          id: doc.docId,
          displayName: doc.title,
          author: doc.author,
          internalRelPath: AppData.storage.docRelPath(doc.docId),
          folderId: targetParentId,
        );
      }
    }
    // 2. Mover Folders
    for (final folderId in folderIds) {
      if (folderId == targetParentId) continue;
      final f = AppData.getFolderById(folderId);
      if (f != null) {
        await AppData.db.upsertFolder(
          id: f.id,
          name: f.name,
          position: f.position,
          parentId: targetParentId == 'root' ? null : targetParentId,
        );
      }
    }
    // NOTA: El llamador es responsable de actualizar el estado local (AppData) o refrescar.
  }

  static int countItems({required List<String> docIds, required List<String> folderIds}) {
    int total = docIds.length;
    // Count folders and their contents
    for (final fId in folderIds) {
      total += 1; // The folder itself
      total += _countDocsInFolderRecursive(fId);
    }
    return total;
  }

  static int _countDocsInFolderRecursive(String folderId) {
    int count = 0;
    // Direct docs
    count += AppData.library.where((s) => s.folderId == folderId).length;
    // Subfolders
    final subFolders = AppData.folders.where((f) => f.parentId == folderId);
    count += subFolders.length;
    for (final sub in subFolders) {
      count += _countDocsInFolderRecursive(sub.id);
    }
    return count;
  }

  static Future<void> deleteItems({
    required List<String> docIds,
    required List<String> folderIds,
    Function(int)? onProgress,
  }) async {
    int count = 0;
    void tick() {
      count++;
      if (onProgress != null) onProgress(count);
    }

    for (final id in docIds) {
      await AppData.db.softDeleteDoc(id);
      tick();
    }
    for (final id in folderIds) {
      await _softDeleteFolderRecursive(id, onProgress: tick);
    }
  }

  static Future<void> _softDeleteFolderRecursive(String folderId, {required Function() onProgress}) async {
    // Soft-delete subfolders
    final childrenF = AppData.folders.where((f) => f.parentId == folderId).toList();
    for (final child in childrenF) {
      await _softDeleteFolderRecursive(child.id, onProgress: onProgress);
    }
    // Soft-delete docs
    final childrenD = AppData.library.where((d) => d.folderId == folderId).toList();
    for (final doc in childrenD) {
      await AppData.db.softDeleteDoc(doc.docId);
      onProgress();
    }
    // Soft-delete the folder itself
    await AppData.db.softDeleteFolder(folderId);
    onProgress();
  }

  // --- RESTORE ---

  /// Restaura documentos y carpetas de la papelera.
  ///
  /// Si el contenedor de un elemento sigue en la papelera (o ya no existe),
  /// el elemento se restaura en la RAÍZ. Así nunca queda "colgando" de una
  /// carpeta oculta (y nunca se purga junto con ella más tarde).
  /// Todo ocurre en una transacción.
  static Future<void> restoreItems({
    required List<String> docIds, 
    required List<String> folderIds,
    Function(int)? onProgress,
  }) async {
    int count = 0;
    void tick() {
      count++;
      if (onProgress != null) onProgress(count);
    }

    await AppData.db.transaction(() async {
      for (final id in folderIds) {
        await _restoreFolderRecursive(id, onProgress: tick);
        final folder = await AppData.db.getFolderById(id);
        if (folder != null && !await _isFolderVisible(folder.parentId)) {
          await AppData.db.setFolderParent(id, null);
        }
      }
      for (final id in docIds) {
        final doc = await AppData.db.getDocById(id);
        if (doc == null) continue;
        await AppData.db.restoreDoc(id);
        if (!await _isFolderVisible(doc.folderId)) {
          await AppData.db.setDocFolder(id, 'root');
        }
        tick();
      }
    });
  }

  /// `true` si la carpeta existe y no está en la papelera (o es la raíz).
  static Future<bool> _isFolderVisible(String? folderId) async {
    if (folderId == null || folderId == 'root') return true;
    final f = await AppData.db.getFolderById(folderId);
    return f != null && !f.isDeleted;
  }

  static Future<void> _restoreFolderRecursive(String folderId, {required Function() onProgress}) async {
    // Se restaura según la DB, porque la memoria solo tiene lo no borrado.
    final dbFolders = await AppData.db.getDeletedFolders();
    final childrenF = dbFolders.where((f) => f.parentId == folderId).toList();
    for (final child in childrenF) {
      await _restoreFolderRecursive(child.id, onProgress: onProgress);
    }

    final dbDocs = await AppData.db.getDeletedDocs();
    final childrenD = dbDocs.where((d) => d.folderId == folderId).toList();
    for (final doc in childrenD) {
      await AppData.db.restoreDoc(doc.id);
      onProgress();
    }
    await AppData.db.restoreFolder(folderId);
    onProgress();
  }

  // --- PERMANENT DELETE (PURGA) ---

  /// Elimina definitivamente elementos de la papelera.
  ///
  /// Reglas de seguridad:
  /// - Solo se purgan documentos que ESTÁN en la papelera. Un documento activo
  ///   nunca se borra, aunque se pida explícitamente.
  /// - Al purgar una carpeta, los documentos o subcarpetas ACTIVOS que tenga
  ///   adentro se rescatan a la raíz en lugar de borrarse.
  /// - La carpeta raíz nunca se purga.
  /// - Las filas de DB se borran en una transacción; los archivos PDF se
  ///   borran recién después del commit.
  static Future<void> permanentlyDeleteItems({
    required List<String> docIds,
    required List<String> folderIds,
    Function(int)? onProgress,
  }) async {
    int count = 0;
    void tick() {
      count++;
      if (onProgress != null) onProgress(count);
    }

    final purgedDocs = <DocsTableData>[];

    await AppData.db.transaction(() async {
      for (final id in docIds) {
        final doc = await AppData.db.getDocById(id);
        if (doc != null && doc.isDeleted) {
          await _purgeDocRows(doc);
          purgedDocs.add(doc);
        }
        tick();
      }
      for (final fId in folderIds) {
        await _purgeFolderRecursive(fId, purgedDocs, onProgress: tick);
      }
    });

    await _deleteDocFiles(purgedDocs);
  }

  static Future<void> _purgeFolderRecursive(
    String folderId,
    List<DocsTableData> purgedDocs, {
    required Function() onProgress,
  }) async {
    if (folderId == 'root') return;

    final allDocs = await AppData.db.getAllDocs();
    for (final d in allDocs.where((d) => d.folderId == folderId)) {
      if (d.isDeleted) {
        await _purgeDocRows(d);
        purgedDocs.add(d);
      } else {
        // Documento activo dentro de una carpeta en la papelera: se rescata.
        await AppData.db.setDocFolder(d.id, 'root');
      }
      onProgress();
    }

    final allFolders = await AppData.db.getAllFolders();
    for (final s in allFolders.where((f) => f.parentId == folderId)) {
      if (s.isDeleted) {
        await _purgeFolderRecursive(s.id, purgedDocs, onProgress: onProgress);
      } else {
        await AppData.db.setFolderParent(s.id, null);
      }
    }

    await AppData.db.deleteFolder(folderId);
    onProgress();
  }

  /// Borra de la DB todo lo asociado a un documento (sin tocar archivos).
  static Future<void> _purgeDocRows(DocsTableData doc) async {
    await AppData.db.deleteSetlistItemsByDocId(doc.id);
    await AppData.db.deleteDocStateByDocId(doc.id);
    await AppData.db.deleteAnnotationsForDoc(doc.id);
    await AppData.db.deleteDocById(doc.id);
  }

  /// Borra los PDFs y puntos de restauración de documentos ya purgados.
  /// Los errores se registran pero no interrumpen (un archivo huérfano es
  /// preferible a una fila sin archivo).
  static Future<void> _deleteDocFiles(List<DocsTableData> docs) async {
    for (final d in docs) {
      try {
        final file = File(AppData.storage.absPathFromRelPath(d.internalRelPath));
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Warning: no se pudo borrar el archivo de ${d.id}: $e');
      }
      await PageEditRepository.discardUndo(d.id);
    }
  }

  /// Purga definitiva de un documento EN LA PAPELERA (no-op si está activo).
  static Future<void> permanentlyDeleteScore(String docId) =>
      permanentlyDeleteItems(docIds: [docId], folderIds: const []);

  @Deprecated('Use permanentlyDeleteScore instead')
  static Future<void> deleteScore(String docId) async {
    await AppData.db.softDeleteDoc(docId);
  }

  // ---------------------------------------------------------------------------
  // HELPERS DE RECURSIVIDAD Y BÚSQUEDA
  // ---------------------------------------------------------------------------

  static Set<String> getRecursiveFolderIds(String startFolderId) {
    final Set<String> ids = {startFolderId};
    final children = AppData.folders.where((f) => f.parentId == startFolderId);
    for (final child in children) {
      ids.addAll(getRecursiveFolderIds(child.id));
    }
    return ids;
  }

  static List<String> getFlatDocIdsFromOrderedSelection(List<String> mixedIds) {
    final uniqueIds = <String>{};
    for (final id in mixedIds) {
      if (AppData.getScoreById(id) != null) {
        uniqueIds.add(id);
      } else if (AppData.getFolderById(id) != null) {
        uniqueIds.addAll(_getDocsInFolderRecursive(id));
      }
    }
    return uniqueIds.toList();
  }

  static List<String> _getDocsInFolderRecursive(String folderId) {
    final out = <String>[];
    // Docs directos
    final directDocs = AppData.library.where((s) => s.folderId == folderId).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    for (final d in directDocs) {
      out.add(d.docId);
    }
    // Subcarpetas
    final subFolders = AppData.folders.where((f) => f.parentId == folderId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final sub in subFolders) {
      out.addAll(_getDocsInFolderRecursive(sub.id));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // PDF STATE HELPERS (Movidos desde AppData)
  // ---------------------------------------------------------------------------

  // Cache en memoria para no abrir el PDF cada vez que scrolleamos
  static final Map<String, int> _pagesCountCache = {};
  static final Map<String, int> _lastPageCache = {};

  static Future<int> getPagesCountForPath(String path) async {
    if (_pagesCountCache.containsKey(path)) return _pagesCountCache[path]!;
    try {
      final bytes = await File(path).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final c = doc.pages.count;
      doc.dispose(); // Importante cerrar/dispose
      _pagesCountCache[path] = c;
      return c;
    } catch (_) {
      return 0;
    }
  }

  /// Invalidates the cached page count for a specific path.
  /// Call this after modifying a PDF (adding/removing pages).
  static void invalidatePageCountCache(String path) {
    _pagesCountCache.remove(path);
  }

  static int getLastPageForDocId(String docId) => _lastPageCache[docId] ?? 1;

  static void setLastPageForDocId(String docId, int page) {
    _lastPageCache[docId] = page;
    // Fire and forget a la DB para no bloquear UI
    AppData.db.upsertLastPage(docId: docId, lastPage: page);
  }

  static Future<void> hydrateDocStates() async {
    final states = await AppData.db.getAllDocStates();
    _lastPageCache.clear();
    for (final s in states) {
      _lastPageCache[s.docId] = s.lastPage;
    }
  }
}
