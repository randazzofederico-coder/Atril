import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../models/setlist.dart';
import '../app_data.dart';

class LibraryRepository {
  
  // ---------------------------------------------------------------------------
  // FOLDERS
  // ---------------------------------------------------------------------------

  static Future<String> createFolder({
    required String name,
    required String parentId,
    bool refresh = true,
  }) async {
    final id = AppData.newFolderId();
    // Calculamos posición basada en los folders actuales en memoria
    final siblings = AppData.folders.where((f) => (f.parentId ?? 'root') == parentId).length;
    
    await AppData.db.createFolder(
      id: id,
      name: name,
      parentId: parentId == 'root' ? null : parentId,
      position: siblings,
    );
    
    if (refresh) await AppData.refreshLibrary();
    return id;
  }

  static Future<void> renameFolder(String folderId, String newName) async {
    final f = AppData.getFolderById(folderId);
    if (f == null) return;

    await AppData.db.upsertFolder(
      id: f.id,
      name: newName,
      parentId: f.parentId, // Mantenemos el mismo padre
      position: f.position, // Mantenemos la misma posición
    );
    await AppData.refreshLibrary();
  }

  // Cambiamos la firma para aceptar (opcionalmente) un nuevo autor
  static Future<void> updateScoreMetadata({
    required String docId, 
    required String newTitle, 
    required String newAuthor
  }) async {
    final s = AppData.getScoreById(docId);
    if (s == null) return;
    
    // Mantenemos el path relativo interno igual
    final relPath = AppData.storage.docRelPath(s.docId);
    
    await AppData.db.upsertDoc(
      id: s.docId,
      displayName: newTitle, // Actualizamos Título
      author: newAuthor,     // Actualizamos Autor
      internalRelPath: relPath,
      folderId: s.folderId,
    );
    await AppData.refreshLibrary();
  }

  // ---------------------------------------------------------------------------
  // SCORES
  // ---------------------------------------------------------------------------

  static Future<void> renameScore(String docId, String newTitle) async {
    final s = AppData.getScoreById(docId);
    if (s == null) return;
    
    final relPath = AppData.storage.docRelPath(s.docId);
    await AppData.db.upsertDoc(
      id: s.docId,
      displayName: newTitle,
      author: s.author,
      internalRelPath: relPath,
      folderId: s.folderId,
    );
    await AppData.refreshLibrary();
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
    await AppData.refreshLibrary();
  }

  static Future<void> deleteItems({
    required List<String> docIds,
    required List<String> folderIds,
  }) async {
    for (final id in docIds) {
      await deleteScore(id, refresh: false);
    }
    for (final id in folderIds) {
      await _deleteFolderRecursive(id);
    }
    await AppData.refreshLibrary();
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
      await deleteScore(doc.docId, refresh: false);
    }
    // Borrar la carpeta en sí
    await AppData.db.deleteFolder(folderId);
  }

  static Future<void> deleteScore(String docId, {bool refresh = true}) async {
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
    if (refresh) await AppData.refreshLibrary();
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