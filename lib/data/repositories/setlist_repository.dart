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

  /// Quita duplicados conservando el orden (la DB no admite el mismo tema
  /// dos veces en un setlist: PK setlistId+docId).
  static List<String> _dedupe(Iterable<String> ids) {
    final seen = <String>{};
    return [for (final id in ids) if (seen.add(id)) id];
  }

  static Future<void> addSetlist(Setlist setlist) async {
    final ids = _dedupe(setlist.docIds);
    await AppData.db.transaction(() async {
      await AppData.db.upsertSetlist(id: setlist.setlistId, name: setlist.name);
      await AppData.db.replaceSetlistItems(setlistId: setlist.setlistId, orderedDocIds: ids);
    });
    // AppData se encargará de refrescar la UI después de llamar a esto
  }

  static Future<void> deleteSetlist(String setlistId) async {
    await AppData.db.deleteSetlistById(setlistId);
  }

  /// Persiste [newOrder] y recién entonces actualiza la memoria. Si la DB
  /// falla, la memoria queda como estaba (no divergen).
  static Future<void> _save(Setlist s, List<String> newOrder) async {
    final ids = _dedupe(newOrder);
    await AppData.db.replaceSetlistItems(setlistId: s.setlistId, orderedDocIds: ids);
    s.docIds
      ..clear()
      ..addAll(ids);
  }

  static Future<void> addDocsToSetlist(String setlistId, List<String> newIds) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    await _save(s, [...s.docIds, ...newIds]);
  }

  static Future<void> reorderDocInSetlist(String setlistId, int oldIdx, int newIdx) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    if (oldIdx < 0 || oldIdx >= s.docIds.length) return;

    // Se actualiza la memoria al instante (la lista reordenable lo necesita
    // para no "saltar") y se revierte si la DB falla.
    final previous = List<String>.of(s.docIds);
    if (newIdx > oldIdx) newIdx -= 1;
    final item = s.docIds.removeAt(oldIdx);
    s.docIds.insert(newIdx.clamp(0, s.docIds.length), item);

    try {
      await AppData.db.replaceSetlistItems(setlistId: setlistId, orderedDocIds: _dedupe(s.docIds));
    } catch (e) {
      s.docIds
        ..clear()
        ..addAll(previous);
      rethrow;
    }
  }
  
  static Future<void> removeDocFromSetlist(String setlistId, String docId) async {
    final s = AppData.getSetlistById(setlistId);
    if (s == null) return;
    await _save(s, s.docIds.where((id) => id != docId).toList());
  }
}
