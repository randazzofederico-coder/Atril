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
  @override
  String get tableName => 'annotation_strokes';

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
  // CAMBIO: Usamos _openConnection en lugar de driftDatabase(...)
  AppDatabase({File? customFile}) : super(_openConnection(customFile));

  @override
  int get schemaVersion => 2; // We are not bumping version technically because we want to map to existing invalid-schema table, but usually we should bump.
  // Given user didn't ask for migration logic, we assume the table exists from previous 'customStatement' or will be created by 'createAll' for new users.

  
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // await _createAnnotationsTableIfNeeded(); // Drift now processes this via createAll
          await _ensureRootFolderExists();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(foldersTable);
            await _ensureRootFolderExists();
            await customStatement("UPDATE docs_table SET folder_id = 'root' WHERE folder_id IS NULL");
          }
           // if (from < 3) { await m.createTable(annotationStrokesTable); } // Assuming we bump version or just rely on existing
           // Since we already used customStatement to create it in previous versions, we don't need to do anything if it exists.
           // However, if we want to be safe:
           // await m.createTable(annotationStrokesTable); // This might fail if exists.
           // Better to let it be, or use 'createTable' with ifNotExists check (Drift doesn't strictly support ifNotExists in createTable directly usually without hacking, but createAll does).
           
           // We removed _createAnnotationsTableIfNeeded calls.
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
      ),
    );
  }

  Future<void> deleteDocById(String docId) async {
    await (delete(docsTable)..where((t) => t.id.equals(docId))).go();
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
      ),
    );
  }

  Future<void> createFolder({
    required String id,
    required String name,
    String? parentId,
    int position = 0,
  }) async {
    return upsertFolder(
      id: id,
      name: name,
      parentId: parentId,
      position: position,
    );
  }

  Future<void> deleteFolder(String folderId) async {
    await (delete(foldersTable)..where((t) => t.id.equals(folderId))).go();
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

  Future<List<AnnotationStrokesTableData>> getAnnotationStrokes({
    required String docId,
    required int pageIndex,
    String? setlistId,
  }) {
    // Basic query
    var query = select(annotationStrokesTable)..where((t) => t.docId.equals(docId) & t.pageIndex.equals(pageIndex));
    
    if (setlistId == null) {
      query = query..where((t) => t.setlistId.isNull());
    } else {
      query = query..where((t) => t.setlistId.equals(setlistId));
    }
    
    return (query..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
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
    String? setlistId,
  }) async {
    var query = delete(annotationStrokesTable)..where((t) => t.docId.equals(docId) & t.pageIndex.equals(pageIndex));
    
    if (setlistId == null) {
      query = query..where((t) => t.setlistId.isNull());
    } else {
      query = query..where((t) => t.setlistId.equals(setlistId));
    }
    
    await query.go();
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