import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../models/setlist.dart';
import '../../models/score.dart';
import '../../models/folder.dart';
import '../app_data.dart';

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

  static Future<void> deleteItems({
    required List<String> docIds,
    required List<String> folderIds,
  }) async {
    for (final id in docIds) {
      await deleteScore(id);
    }
    for (final id in folderIds) {
      await _deleteFolderRecursive(id);
    }
    // NOTA: El llamador es responsable de refrescar.
  }

  static Future<void> _deleteFolderRecursive(String folderId) async {
    // Borrar subcarpetas
    final childrenF = AppData.folders.where((f) => f.parentId == folderId).toList();
    for (final child in childrenF) {
      await _deleteFolderRecursive(child.id);
    }
    // Borrar docs dentro
    final childrenD = AppData.library.where((d) => d.folderId == folderId).toList();
    for (final doc in childrenD) {
      await deleteScore(doc.docId);
    }
    // Borrar la carpeta en sí
    await AppData.db.deleteFolder(folderId);
  }

  static Future<void> deleteScore(String docId) async {
    final score = AppData.getScoreById(docId);
    if (score == null) return;

    // 1. Limpiar referencias en Setlists
    final changedSetlists = <Setlist>[];
    for (final s in AppData.setlists) {
      if (s.docIds.contains(docId)) {
        s.docIds.removeWhere((id) => id == docId);
        changedSetlists.add(s);
      }
    }

    await AppData.db.deleteSetlistItemsByDocId(docId);
    for (final s in changedSetlists) {
      await AppData.db.replaceSetlistItems(setlistId: s.setlistId, orderedDocIds: s.docIds);
    }

    // 2. Borrar datos de la partitura
    await AppData.db.deleteDocStateByDocId(docId);
    await AppData.db.deleteDocById(docId);
    await AppData.storage.deleteDocFile(docId);
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