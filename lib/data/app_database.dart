import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart'; // Importante para NativeDatabase
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// -----------------------------------------------------------------------------
// Drift schema (v2)
// -----------------------------------------------------------------------------

class DocsTable extends Table {
  TextColumn get id => text()(); // docId
  TextColumn get displayName => text()();
  TextColumn get author => text().nullable()();
  TextColumn get internalRelPath => text()();
  TextColumn get folderId => text().nullable().references(FoldersTable, #id)();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FoldersTable extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(FoldersTable, #id)();
  TextColumn get name => text()();
  IntColumn get position => integer()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SetlistsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SetlistItemsTable extends Table {
  TextColumn get setlistId => text().references(SetlistsTable, #id)();
  TextColumn get docId => text().references(DocsTable, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {setlistId, docId};
}

class DocStateTable extends Table {
  TextColumn get docId => text().references(DocsTable, #id)();
  IntColumn get lastPage => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {docId};
}

class AnnotationStrokesTable extends Table {
  // @override
  // String get tableName => 'annotation_strokes';

  TextColumn get id => text()();
  TextColumn get docId => text()();
  TextColumn get setlistId => text().nullable()();
  IntColumn get pageIndex => integer()();
  TextColumn get tool => text()();
  RealColumn get width => real()();
  TextColumn get pointsJson => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}


// --- APERTURA DE CONEXIÓN EXPLÍCITA ---
LazyDatabase _openConnection([File? customFile]) {
  return LazyDatabase(() async {
    if (customFile != null) {
      return NativeDatabase.createInBackground(customFile);
    }
    // Aquí definimos explícitamente que la DB viva en la carpeta de Documentos
    // para que coincida con donde la busca el BackupManager.
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'atril.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftDatabase(
  tables: [DocsTable, SetlistsTable, SetlistItemsTable, DocStateTable, FoldersTable, AnnotationStrokesTable],
)
class AppDatabase extends _$AppDatabase {
  // CAMBIO: Constructor flexible para permitir testing (in-memory) o uso normal (disco)
  AppDatabase({QueryExecutor? executor, File? customFile}) : super(executor ?? _openConnection(customFile));

  @override
  int get schemaVersion => 4; 

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _ensureRootFolderExists();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(foldersTable);
            await _ensureRootFolderExists();
            await customStatement("UPDATE docs_table SET folder_id = 'root' WHERE folder_id IS NULL");
          }
           if (from < 3) {
             await m.createTable(annotationStrokesTable);
           }
           if (from < 4) {
             await m.addColumn(docsTable, docsTable.isDeleted);
             await m.addColumn(docsTable, docsTable.deletedAt);
             await m.addColumn(foldersTable, foldersTable.isDeleted);
             await m.addColumn(foldersTable, foldersTable.deletedAt);
           }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // Se eliminó _createAnnotationsTableIfNeeded porque ahora es una tabla nativa de Drift.

  Future<void> _ensureRootFolderExists() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      "INSERT OR IGNORE INTO folders_table (id, parent_id, name, position, created_at, updated_at) VALUES ('root', NULL, 'Biblioteca', 0, ?, ?)",
      [now, now],
    );
  }

  // ---------------------------------------------------------------------------
  // Docs
  // ---------------------------------------------------------------------------

  Future<List<DocsTableData>> getAllDocs() {
    return (select(docsTable)..orderBy([(t) => OrderingTerm.asc(t.displayName)])).get();
  }

  Future<void> upsertDoc({
    required String id,
    required String displayName,
    required String author,
    required String internalRelPath,
    String? folderId,
    bool isDeleted = false,
    int? deletedAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(docsTable).insertOnConflictUpdate(
      DocsTableCompanion.insert(
        id: id,
        displayName: displayName,
        author: Value(author),
        internalRelPath: internalRelPath,
        folderId: Value(folderId ?? 'root'),
        createdAt: now,
        updatedAt: now,
        isDeleted: Value(isDeleted),
        deletedAt: Value(deletedAt),
      ),
    );
  }

  Future<void> deleteDocById(String docId) async {
    await (delete(docsTable)..where((t) => t.id.equals(docId))).go();
  }

  // --- TRASH / SOFT DELETE DOCS ---

  Future<void> softDeleteDoc(String docId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(docsTable)..where((t) => t.id.equals(docId))).write(
      DocsTableCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
      ),
    );
  }

  Future<void> restoreDoc(String docId) async {
    await (update(docsTable)..where((t) => t.id.equals(docId))).write(
      const DocsTableCompanion(
        isDeleted: Value(false),
        deletedAt: Value(null),
      ),
    );
  }

  Future<List<DocsTableData>> getDeletedDocs() {
     return (select(docsTable)..where((t) => t.isDeleted.equals(true))).get();
  }

  Future<void> deleteDocStateByDocId(String docId) async {
    await (delete(docStateTable)..where((t) => t.docId.equals(docId))).go();
  }

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  Future<List<FoldersTableData>> getAllFolders() {
    return (select(foldersTable)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
  }

  Future<void> upsertFolder({
    required String id,
    required String name,
    String? parentId,
    required int position,
    bool isDeleted = false,
    int? deletedAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(foldersTable).insertOnConflictUpdate(
      FoldersTableCompanion.insert(
        id: id,
        name: name,
        parentId: Value(parentId),
        position: position,
        createdAt: now,
        updatedAt: now,
        isDeleted: Value(isDeleted),
        deletedAt: Value(deletedAt),
      ),
    );
  }

  Future<void> createFolder({
    required String id,
    required String name,
    String? parentId,
    int position = 0,
    bool isDeleted = false,
    int? deletedAt,
  }) async {
    return upsertFolder(
      id: id,
      name: name,
      parentId: parentId,
      position: position,
      isDeleted: isDeleted,
      deletedAt: deletedAt,
    );
  }

  Future<void> deleteFolder(String folderId) async {
    await (delete(foldersTable)..where((t) => t.id.equals(folderId))).go();
  }

  // --- TRASH / SOFT DELETE FOLDERS ---

  Future<void> softDeleteFolder(String folderId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(foldersTable)..where((t) => t.id.equals(folderId))).write(
      FoldersTableCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
      ),
    );
  }

  Future<void> restoreFolder(String folderId) async {
    await (update(foldersTable)..where((t) => t.id.equals(folderId))).write(
      const FoldersTableCompanion(
        isDeleted: Value(false),
        deletedAt: Value(null),
      ),
    );
  }

  Future<List<FoldersTableData>> getDeletedFolders() {
    return (select(foldersTable)..where((t) => t.isDeleted.equals(true))).get();
  }

  // ---------------------------------------------------------------------------
  // Setlists
  // ---------------------------------------------------------------------------

  Future<List<SetlistsTableData>> getAllSetlists() {
    return (select(setlistsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<void> upsertSetlist({
    required String id,
    required String name,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(setlistsTable).insertOnConflictUpdate(
      SetlistsTableCompanion.insert(
        id: id,
        name: name,
        notes: Value(notes),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteSetlistById(String setlistId) async {
    await transaction(() async {
      await (delete(setlistItemsTable)..where((t) => t.setlistId.equals(setlistId))).go();
      await (delete(setlistsTable)..where((t) => t.id.equals(setlistId))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Setlist items
  // ---------------------------------------------------------------------------

  Future<List<SetlistItemsTableData>> getItemsForSetlist(String setlistId) {
    return (select(setlistItemsTable)
          ..where((t) => t.setlistId.equals(setlistId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<void> replaceSetlistItems({
    required String setlistId,
    required List<String> orderedDocIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await (delete(setlistItemsTable)..where((t) => t.setlistId.equals(setlistId))).go();

      var pos = 0;
      for (final docId in orderedDocIds) {
        if (docId.isEmpty) continue;

        await into(setlistItemsTable).insert(
          SetlistItemsTableCompanion.insert(
            setlistId: setlistId,
            docId: docId,
            position: pos,
          ),
        );
        pos++;
      }
      await (update(setlistsTable)..where((t) => t.id.equals(setlistId))).write(
        SetlistsTableCompanion(updatedAt: Value(now)),
      );
    });
  }

  Future<void> deleteSetlistItemsByDocId(String docId) async {
    await (delete(setlistItemsTable)..where((t) => t.docId.equals(docId))).go();
  }

  // ---------------------------------------------------------------------------
  // Annotations
  // ---------------------------------------------------------------------------
  //
  // Una capa global por documento. La columna `setlist_id` se conserva por
  // compatibilidad con datos viejos, pero la app ya no crea capas por setlist:
  // las lecturas "visibles" filtran `setlist_id IS NULL`. Las operaciones de
  // mantenimiento (remap, borrar, deshacer) actúan sobre todas las filas del
  // documento para no dejar huérfanos.

  Future<List<AnnotationStrokesTableData>> getAnnotationStrokes({
    required String docId,
    required int pageIndex,
  }) {
    final query = select(annotationStrokesTable)
      ..where((t) =>
          t.docId.equals(docId) & t.pageIndex.equals(pageIndex) & t.setlistId.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Todos los trazos visibles de un documento (todas las páginas).
  Future<List<AnnotationStrokesTableData>> getAnnotationStrokesForDoc({
    required String docId,
  }) {
    final query = select(annotationStrokesTable)
      ..where((t) => t.docId.equals(docId) & t.setlistId.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.pageIndex),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.get();
  }

  /// Todos los trazos de la DB (usado al importar/mergear backups).
  Future<List<AnnotationStrokesTableData>> getAllAnnotationStrokes() {
    return select(annotationStrokesTable).get();
  }

  /// Todas las filas de un documento (incluidas capas legacy por setlist).
  Future<List<AnnotationStrokesTableData>> getAllAnnotationStrokesForDocAllLayers(String docId) {
    return (select(annotationStrokesTable)..where((t) => t.docId.equals(docId))).get();
  }

  /// Reubica los trazos de un documento tras editar sus páginas.
  ///
  /// [pageMapping]: página vieja (1-based) → página nueva (1-based).
  /// Los trazos de páginas que no figuran en el mapa (páginas eliminadas)
  /// se borran. Atómico (transacción).
  Future<void> remapAnnotationPages(String docId, Map<int, int> pageMapping) async {
    await transaction(() async {
      final rows = await getAllAnnotationStrokesForDocAllLayers(docId);
      for (final r in rows) {
        final newPage = pageMapping[r.pageIndex];
        if (newPage == null) {
          await (delete(annotationStrokesTable)..where((t) => t.id.equals(r.id))).go();
        } else if (newPage != r.pageIndex) {
          await (update(annotationStrokesTable)..where((t) => t.id.equals(r.id)))
              .write(AnnotationStrokesTableCompanion(pageIndex: Value(newPage)));
        }
      }
    });
  }

  /// Reemplaza TODOS los trazos de un documento por [rows] (usado para deshacer).
  Future<void> replaceAnnotationsForDoc(String docId, List<AnnotationStrokesTableData> rows) async {
    await transaction(() async {
      await (delete(annotationStrokesTable)..where((t) => t.docId.equals(docId))).go();
      for (final r in rows) {
        await into(annotationStrokesTable).insertOnConflictUpdate(r);
      }
    });
  }

  /// Borra todas las anotaciones de un documento (al purgarlo definitivamente).
  Future<void> deleteAnnotationsForDoc(String docId) async {
    await (delete(annotationStrokesTable)..where((t) => t.docId.equals(docId))).go();
  }

  /// IDs de documentos que tienen al menos una anotación visible.
  Future<Set<String>> getAnnotatedDocIds() async {
    final query = selectOnly(annotationStrokesTable, distinct: true)
      ..addColumns([annotationStrokesTable.docId])
      ..where(annotationStrokesTable.setlistId.isNull());
    final rows = await query.get();
    return rows
        .map((r) => r.read(annotationStrokesTable.docId))
        .whereType<String>()
        .toSet();
  }

  Future<void> insertAnnotationStroke(AnnotationStrokesTableCompanion entry) async {
    await into(annotationStrokesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteAnnotationStrokeById(String id) async {
    await (delete(annotationStrokesTable)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteAnnotationStrokesForPage({
    required String docId,
    required int pageIndex,
  }) async {
    await (delete(annotationStrokesTable)
          ..where((t) =>
              t.docId.equals(docId) & t.pageIndex.equals(pageIndex) & t.setlistId.isNull()))
        .go();
  }

  // ---------------------------------------------------------------------------
  // Doc state
  // ---------------------------------------------------------------------------

  Future<List<DocStateTableData>> getAllDocStates() {
    return select(docStateTable).get();
  }

  Future<void> upsertLastPage({required String docId, required int lastPage}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(docStateTable).insertOnConflictUpdate(
      DocStateTableCompanion.insert(
        docId: docId,
        lastPage: (lastPage < 1 ? 1 : lastPage),
        updatedAt: now,
      ),
    );
  }
}
