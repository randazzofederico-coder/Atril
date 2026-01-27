import '../../models/setlist.dart';
import '../app_data.dart'; // Necesario para acceder a AppData.db y AppData.setlists

class SetlistRepository {
  
  /// Genera un nombre único para el setlist (ej: "Concierto (2)")
  static String uniqueSetlistName(String desiredName) {
    final base = desiredName.trim();
    if (base.isEmpty) return 'Sin Nombre';
    
    // Accedemos a la lista actual en memoria para verificar duplicados
    final exists = AppData.setlists.any((s) => s.name.toLowerCase() == base.toLowerCase());
    if (!exists) return base;
    
    var n = 2;
    while (true) {
      final cand = '$base ($n)';
      if (!AppData.setlists.any((s) => s.name.toLowerCase() == cand.toLowerCase())) return cand;
      n++;
    }
  }

  static Future<void> addSetlist(Setlist setlist) async {
    await AppData.db.transaction(() async {
      await AppData.db.upsertSetlist(id: setlist.setlistId, name: setlist.name);
      await AppData.db.replaceSetlistItems(setlistId: setlist.setlistId, orderedDocIds: setlist.docIds);
    });
    // AppData se encargará de refrescar la UI después de llamar a esto
  }

  static Future<void> deleteSetlist(String setlistId) async {
    await AppData.db.deleteSetlistById(setlistId);
  }

  static Future<void> addDocsToSetlist(String setlistId, List<String> newIds) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    
    // Modificamos el objeto en memoria
    s.docIds.addAll(newIds);
    
    // Persistimos en DB
    await AppData.db.replaceSetlistItems(setlistId: setlistId, orderedDocIds: s.docIds);
  }

  static Future<void> reorderDocInSetlist(String setlistId, int oldIdx, int newIdx) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    
    // Lógica de reordenamiento de lista
    if (newIdx > oldIdx) newIdx -= 1;
    final item = s.docIds.removeAt(oldIdx);
    s.docIds.insert(newIdx, item);
    
    // Persistimos
    await AppData.db.replaceSetlistItems(setlistId: setlistId, orderedDocIds: s.docIds);
  }
  
  static Future<void> removeDocFromSetlist(String setlistId, String docId) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    
    s.docIds.remove(docId);
    await AppData.db.replaceSetlistItems(setlistId: setlistId, orderedDocIds: s.docIds);
  }
}