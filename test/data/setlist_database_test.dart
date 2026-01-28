import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Setlist Database Tests', () {
    // Helper para crear Docs necesarios para los setlists
    Future<void> createDummyDocs(List<String> ids) async {
      for (final id in ids) {
        await db.upsertDoc(
          id: id,
          displayName: 'Doc $id',
          author: 'Tester',
          internalRelPath: 'path/$id',
        );
      }
    }

    test('Should create and retrieve a Setlist', () async {
      await db.upsertSetlist(id: 's_1', name: 'Mi Setlist');
      
      final setlists = await db.getAllSetlists();
      expect(setlists.length, 1);
      expect(setlists.first.id, 's_1');
      expect(setlists.first.name, 'Mi Setlist');
    });

    test('Should add items in order to a Setlist', () async {
      // 1. Crear Setlist
      await db.upsertSetlist(id: 's_1', name: 'Concierto');
      
      // 2. Crear Docs (Foreign Key constraint lo requiere normalmente, 
      // aunque SQLite por defecto a veces es laxo, Drift lo fuerza si se configura)
      final docIds = ['d_1', 'd_2', 'd_3'];
      await createDummyDocs(docIds);

      // 3. Agregar items usando replaceSetlistItems (que limpia y reinserta)
      await db.replaceSetlistItems(
        setlistId: 's_1',
        orderedDocIds: docIds,
      );

      // 4. Verificar recuperación
      final items = await db.getItemsForSetlist('s_1');
      expect(items.length, 3);
      expect(items[0].docId, 'd_1');
      expect(items[0].position, 0);
      expect(items[1].docId, 'd_2');
      expect(items[1].position, 1);
      expect(items[2].docId, 'd_3');
      expect(items[2].position, 2);
    });

    test('Should update order of items', () async {
      await db.upsertSetlist(id: 's_1', name: 'Orden');
      await createDummyDocs(['A', 'B']);

      // Orden original: A, B
      await db.replaceSetlistItems(setlistId: 's_1', orderedDocIds: ['A', 'B']);
      
      var items = await db.getItemsForSetlist('s_1');
      expect(items[0].docId, 'A');

      // Nuevo orden: B, A
      await db.replaceSetlistItems(setlistId: 's_1', orderedDocIds: ['B', 'A']);
      
      items = await db.getItemsForSetlist('s_1');
      expect(items[0].docId, 'B'); // B debería ser el primero (pos 0)
      expect(items[1].docId, 'A'); // A debería ser el segundo (pos 1)
      expect(items[0].position, 0);
    });

    test('Should delete Setlist and cascade delete items', () async {
      await db.upsertSetlist(id: 's_1', name: 'Borrar');
      await createDummyDocs(['d_1']);
      await db.replaceSetlistItems(setlistId: 's_1', orderedDocIds: ['d_1']);

      // Verificar existencia
      expect((await db.getAllSetlists()).length, 1);
      expect((await db.getItemsForSetlist('s_1')).length, 1);

      // Borrar usando método transaccional
      await db.deleteSetlistById('s_1');

      // Verificar limpieza
      expect((await db.getAllSetlists()).length, 0);
      // Los items deberían haberse borrado también
      expect((await db.getItemsForSetlist('s_1')).length, 0);
    });
    
    test('Should clear items for deleted Doc (Referential Integrity Check)', () async {
      // Este test verifica la limpieza manual que hacemos en deleteSetlistItemsByDocId
      // o la integridad referencial si estuviera activada en cascada
      
      await db.upsertSetlist(id: 's_1', name: 'Ref Check');
      await createDummyDocs(['d_dead', 'd_live']);
      
      // Lista: [d_dead, d_live]
      await db.replaceSetlistItems(setlistId: 's_1', orderedDocIds: ['d_dead', 'd_live']);
      
      // Simulamos borrado de documento
      // Nota: En la app real, LibraryRepository llama a deleteSetlistItemsByDocId
      // Aquí probamos directamenet ese método de la DB
      await db.deleteSetlistItemsByDocId('d_dead');
      
      // Al pedir los items, d_dead no debería estar
      final items = await db.getItemsForSetlist('s_1');
      
      // Nota: deleteSetlistItemsByDocId solo borra la fila. 
      // replaceSetlistItems es quien reordena los indices normalmente.
      // Aquí solo esperamos que d_dead desaparezca.
      expect(items.any((i) => i.docId == 'd_dead'), false);
      expect(items.any((i) => i.docId == 'd_live'), true);
    });
  });
}
