import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/score.dart';
import '../models/setlist.dart';
import '../models/folder.dart';
import '../models/annotation_stroke.dart';
import 'app_database.dart';
import 'library_storage.dart';

// --- REPOSITORIOS (FACHADA) ---
// Exportamos para que las pantallas no necesiten cambiar sus imports
import 'repositories/import_repository.dart';
export 'repositories/import_repository.dart';

import 'repositories/setlist_repository.dart';
export 'repositories/setlist_repository.dart';

import 'repositories/library_repository.dart';
export 'repositories/library_repository.dart';

import 'repositories/annotation_repository.dart'; 
export 'repositories/annotation_repository.dart';

import 'repositories/settings_repository.dart';
export 'repositories/settings_repository.dart';

class AppData {
  static AppDatabase db = AppDatabase();
  static final LibraryStorage storage = LibraryStorage.instance;
  static final SettingsRepository settings = SettingsRepository.instance;

  static Future<void>? _initFuture;
  
  // Estado Reactivo
  static final ValueNotifier<ImportState> importState = ValueNotifier(const ImportState());
  static final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> setlistsRevision = ValueNotifier<int>(0);
  
  // Progress Global
  static final ValueNotifier<BackgroundTaskStatus?> backgroundTaskProgress = ValueNotifier<BackgroundTaskStatus?>(null);

  // Navigation Control
  static final ValueNotifier<int> navigationResetTrigger = ValueNotifier<int>(0);

  // Cache en Memoria (Source of Truth para la UI)
  static final List<Score> library = <Score>[];
  static final List<Folder> folders = <Folder>[];
  static final List<Setlist> setlists = <Setlist>[];
  
  // Indices privados para acceso O(1)
  static final Map<String, Score> _scoresById = <String, Score>{};
  static final Map<String, Folder> _foldersById = <String, Folder>{};
  static final Map<String, Setlist> _setlistsById = <String, Setlist>{};

  // Cache de Ordenamiento
  static int _cachedLibrarySortedRevision = -1;
  static List<Score>? _cachedLibrarySorted;

  // --- CICLO DE VIDA ---

  static Future<void> init({bool forceReopen = false}) {
    if (forceReopen) {
      db = AppDatabase();
      _initFuture = null;
    }
    return _initFuture ??= _initInternal();
  }

  static Future<void> closeDbForRestore() async {
    await db.close();
    await Future.delayed(const Duration(milliseconds: 500));
  }

  static Future<void> _initInternal() async {
    await settings.init();
    await storage.init();
    await refreshLibrary();
  }

  static Future<void> refreshLibrary() async {
    await _hydrateAll();
  }

  /// Carga todo desde la DB a la memoria RAM.
  static Future<void> _hydrateAll() async {
    // 1. Folders
    final dbFolders = await db.getAllFolders();
    folders.clear();
    _foldersById.clear();
    for (final f in dbFolders) {
      if (f.id == 'root') continue;
      final folder = Folder(
        id: f.id,
        name: f.name,
        parentId: f.parentId,
        position: f.position,
      );
      folders.add(folder);
      _foldersById[folder.id] = folder;
    }

    // 2. Docs
    final docs = await db.getAllDocs();
    library.clear();
    _scoresById.clear();

    for (final d in docs) {
      final absPath = storage.absPathFromRelPath(d.internalRelPath);
      final score = Score(
        docId: d.id,
        title: d.displayName,
        author: d.author ?? '',
        filePath: absPath,
        folderId: d.folderId ?? 'root',
      );
      library.add(score);
      _scoresById[score.docId] = score;
    }

    // 3. Setlists
    final sls = await db.getAllSetlists();
    setlists.clear();
    _setlistsById.clear();

    for (final s in sls) {
      final items = await db.getItemsForSetlist(s.id);
      final docIds = items
          .map((e) => e.docId)
          .where((id) => id.isNotEmpty)
          .toList(growable: true);
      final setlist = Setlist(setlistId: s.id, name: s.name, docIds: docIds);
      setlists.add(setlist);
      _setlistsById[setlist.setlistId] = setlist;
    }

    // 4. Doc States (Page Persistence)
    await LibraryRepository.hydrateDocStates();

    _notifyLibrary();
    _notifySetlists();
  }

  static void _notifyLibrary() => libraryRevision.value++;
  static void _notifySetlists() => setlistsRevision.value++;
  
  static void triggerNavigationReset() => navigationResetTrigger.value++;

  // --- ID GENERATORS ---
  static int _seq = 0;
  static String newId({String prefix = 'id'}) {
    _seq += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }
  static String newDocId() => newId(prefix: 'd');
  static String newSetlistId() => newId(prefix: 's');
  static String newFolderId() => newId(prefix: 'f');

  // ===========================================================================
  // SELECTORS & CACHE ACCESS (UI HELPERS)
  // ===========================================================================

  static Folder? getFolderById(String id) => _foldersById[id];
  static Score? getScoreById(String id) => _scoresById[id];
  static Setlist? getSetlistById(String id) => _setlistsById[id];

  static List<Score> getLibrarySortedByTitle() {
    final rev = libraryRevision.value;
    if (_cachedLibrarySorted != null && _cachedLibrarySortedRevision == rev) {
      return _cachedLibrarySorted!;
    }
    final sorted = List<Score>.from(library)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    
    _cachedLibrarySorted = sorted;
    _cachedLibrarySortedRevision = rev;
    return sorted;
  }

  static List<Score> materializeSetlist(Setlist s) {
    final out = <Score>[];
    for (final id in s.docIds) {
      final sc = _scoresById[id];
      if (sc != null) out.add(sc);
    }
    return out;
  }

  // ===========================================================================
  // ACTION DELEGATES (FACHADA)
  // Redireccionan a los Repositorios correspondientes.
  // ===========================================================================

  // ===========================================================================
  // HELPER METHODS FOR LOCAL STATE MUTATION (OPTIMIZATION)
  // ===========================================================================

  static void _addFolderLocal(Folder f) {
    folders.add(f);
    _foldersById[f.id] = f;
  }

  static void _updateFolderLocal(Folder f) {
    // Replace in list
    final idx = folders.indexWhere((item) => item.id == f.id);
    if (idx != -1) folders[idx] = f;
    // Replace in map
    _foldersById[f.id] = f;
  }

  // _removeFolderLocal unused

  // _addScoreLocal unused

  static void _updateScoreLocal(Score s) {
     final idx = library.indexWhere((item) => item.docId == s.docId);
     if (idx != -1) library[idx] = s;
     _scoresById[s.docId] = s;
  }

  static void _removeScoreLocal(String id) {
    library.removeWhere((s) => s.docId == id);
    _scoresById.remove(id);
  }

  // ===========================================================================
  // ACTION DELEGATES (FACHADA)
  // Redireccionan a los Repositorios correspondientes.
  // ===========================================================================

  // --- LIBRARY REPOSITORY ---
  
  static Future<String> createFolder({required String name, required String parentId, bool refresh = true}) async {
    // 1. DB Operation (returns Folder object)
    final newFolder = await LibraryRepository.createFolder(name: name, parentId: parentId);
    
    // 2. Local Update
    _addFolderLocal(newFolder);
    _notifyLibrary();
    
    return newFolder.id;
  }
  
  static bool folderNameExists(String name, String parentId) => 
      LibraryRepository.folderNameExists(name, parentId);
  
  static Future<void> updateScoreMetadata(String docId, String newTitle, String newAuthor) async {
    final updatedScore = await LibraryRepository.updateScoreMetadata(docId: docId, newTitle: newTitle, newAuthor: newAuthor);
    if (updatedScore != null) {
      _updateScoreLocal(updatedScore);
      _notifyLibrary();
    }
  }

  static Future<void> renameScore(String docId, String newTitle) async {
    final updatedScore = await LibraryRepository.renameScore(docId, newTitle);
    if (updatedScore != null) {
       _updateScoreLocal(updatedScore);
       _notifyLibrary();
    }
  }
    
  static Future<void> renameFolder(String folderId, String newName) async {
    final updatedFolder = await LibraryRepository.renameFolder(folderId, newName);
    if (updatedFolder != null) {
      _updateFolderLocal(updatedFolder);
      _notifyLibrary();
    }
  }
  
  static Future<void> moveItems({required List<String> docIds, required List<String> folderIds, required String targetParentId}) async {
    await LibraryRepository.moveItems(docIds: docIds, folderIds: folderIds, targetParentId: targetParentId);
    
    // Manual hydration for move
    // It's cheaper to just update the fields locally than re-fetch all
    for (final docId in docIds) {
      final old = _scoresById[docId];
      if (old != null) {
        // Score is immutable, must replace
        final newS = Score(
           docId: old.docId, 
           title: old.title, 
           author: old.author, 
           filePath: old.filePath, 
           folderId: targetParentId // Updated
        );
        _updateScoreLocal(newS);
      }
    }
    
    for (final fId in folderIds) {
      final old = _foldersById[fId];
      if (old != null) {
        final newF = Folder(
           id: old.id, 
           name: old.name, 
           position: old.position, 
           parentId: targetParentId == 'root' ? null : targetParentId
        );
        _updateFolderLocal(newF);
      }
    }
    
    _notifyLibrary();
  }
  
  static Future<void> deleteItems({required List<String> docIds, required List<String> folderIds}) async {
    backgroundTaskProgress.value = const BackgroundTaskStatus(0.0, 'Eliminando items...');
    try {
      await LibraryRepository.deleteItems(docIds: docIds, folderIds: folderIds);
      // Simulating progress or just indefinite? 
      // Repository call is one-shot. 
      // User wants feedback. The spinner is good, but text is strictly requested "Misma logica...".
      // Since we don't know progress inside repo, we just show "Eliminando..."
      await refreshLibrary();
    } finally {
      backgroundTaskProgress.value = null;
    }
  }
  
  static Future<void> deleteScore(String docId, {bool refresh = true}) async {
    await LibraryRepository.deleteScore(docId);
    _removeScoreLocal(docId);
    if (refresh) _notifyLibrary(); 
  }
  
  static String uniqueTitle(String desiredTitle) => 
      LibraryRepository.uniqueTitle(desiredTitle);

  static Set<String> getRecursiveFolderIds(String startFolderId) =>
      LibraryRepository.getRecursiveFolderIds(startFolderId);

  static List<String> getFlatDocIdsFromOrderedSelection(List<String> mixedIds) =>
      LibraryRepository.getFlatDocIdsFromOrderedSelection(mixedIds);

  // --- IMPORT REPOSITORY ---
  static Future<Score> importPdfFromExternalPath({required String sourcePath, required String desiredTitle, String author = '', String targetFolderId = 'root', bool refresh = true}) =>
      ImportRepository.importPdfFromExternalPath(sourcePath: sourcePath, desiredTitle: desiredTitle, author: author, targetFolderId: targetFolderId, refresh: refresh);

  static Future<void> importBatchBackground(List<String> filePaths, String targetFolderId) => 
      ImportRepository.importBatchBackground(filePaths, targetFolderId);
  

  
  static Future<void> importFolderBackground(String path, String targetParentId) => 
      ImportRepository.importFolderBackground(path, targetParentId);

  // --- SETLIST REPOSITORY ---
  static String uniqueSetlistName(String desiredName) => SetlistRepository.uniqueSetlistName(desiredName);
  
  static Future<void> addSetlist(Setlist setlist) async { 
    await SetlistRepository.addSetlist(setlist);
    await refreshLibrary(); 
  }
  
  static Future<void> deleteSetlist(String setlistId) async { 
    await SetlistRepository.deleteSetlist(setlistId); 
    await refreshLibrary();
  }
  
  static Future<void> addDocsToSetlist(String setlistId, List<String> newIds) async { 
    await SetlistRepository.addDocsToSetlist(setlistId, newIds); 
    _notifySetlists();
  }
  
  static Future<void> reorderDocInSetlist(String setlistId, int oldIdx, int newIdx) async { 
    await SetlistRepository.reorderDocInSetlist(setlistId, oldIdx, newIdx); 
    _notifySetlists();
  }
  
  static Future<void> removeDocFromSetlist(String setlistId, String docId) async { 
    await SetlistRepository.removeDocFromSetlist(setlistId, docId); 
    _notifySetlists();
  }

  // --- ANNOTATION REPOSITORY ---
  static Future<List<AnnotationStroke>> getAnnotationStrokesForPage({required String docId, required int pageIndex, String? setlistId}) =>
      AnnotationRepository.getAnnotationStrokesForPage(docId: docId, pageIndex: pageIndex, setlistId: setlistId);

  static Future<void> insertAnnotationStroke(AnnotationStroke s) =>
      AnnotationRepository.insertAnnotationStroke(s);

  static Future<void> deleteAnnotationStroke(String id) =>
      AnnotationRepository.deleteAnnotationStroke(id);

  static Future<void> deleteAnnotationStrokesForPage({required String docId, required int pageIndex, String? setlistId}) =>
      AnnotationRepository.deleteAnnotationStrokesForPage(docId: docId, pageIndex: pageIndex, setlistId: setlistId);

  // --- PDF UTILS (Delegated to LibraryRepository) ---
  static Future<int> getPagesCountForPath(String path) => LibraryRepository.getPagesCountForPath(path);
  static int getLastPageForDocId(String docId) => LibraryRepository.getLastPageForDocId(docId);
  static void setLastPageForDocId(String docId, int page) => LibraryRepository.setLastPageForDocId(docId, page);
}

class BackgroundTaskStatus {
  final double progress; // 0.0 - 1.0
  final String message;
  
  const BackgroundTaskStatus(this.progress, this.message);
  
  String get percentage => '${(progress * 100).toInt()}%';
}