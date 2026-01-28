import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Usamos una base de datos en memoria para cada test
    // Esto asegura aislamiento total entre tests
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase Integration Tests', () {
    test('Should create and retrieve a folder', () async {
      // final now = DateTime.now().millisecondsSinceEpoch; // Unused
      
      // La tabla folders necesita que exista 'root' si se usa FK, 
      // pero Drift no valida FKs en memoria por defecto a menos que se habilite.
      // Sin embargo, nuestra migración onCreate inserta 'root'. 
      // Verifiquemos si la migración corre en NativeDatabase.memory().
      // Sí, Drift ejecuta migraciones al abrir.

      await db.createFolder(
        id: 'f_test',
        name: 'Carpeta de Prueba',
        position: 0,
        parentId: 'root'
      );

      final folders = await db.getAllFolders();
      
      // Debería haber 2: root (creado por migración) + f_test
      expect(folders.length, 2);
      
      final myFolder = folders.firstWhere((f) => f.id == 'f_test');
      expect(myFolder.name, 'Carpeta de Prueba');
      expect(myFolder.parentId, 'root');
    });

    test('Should insert and retrieve a Doc (Score)', () async {
       await db.upsertDoc(
         id: 'd_123', 
         displayName: 'Partitura Test', 
         author: 'Mozart', 
         internalRelPath: 'docs/d_123.pdf'
       );

       final docs = await db.getAllDocs();
       expect(docs.length, 1);
       
       final doc = docs.first;
       expect(doc.id, 'd_123');
       expect(doc.displayName, 'Partitura Test');
       expect(doc.author, 'Mozart');
       expect(doc.folderId, 'root'); // Default
    });

    test('Should update a Doc', () async {
      await db.upsertDoc(
         id: 'd_123', 
         displayName: 'Version 1', 
         author: 'Original', 
         internalRelPath: 'path'
       );

      // Upsert con mismo ID actualiza
      await db.upsertDoc(
         id: 'd_123', 
         displayName: 'Version 2', 
         author: 'Editado', 
         internalRelPath: 'path'
       );

      final docs = await db.getAllDocs();
      expect(docs.length, 1);
      expect(docs.first.displayName, 'Version 2');
      expect(docs.first.author, 'Editado');
    });

    test('Should delete a Doc', () async {
       await db.upsertDoc(id: 'd_1', displayName: 'A', author: '', internalRelPath: '');
       await db.upsertDoc(id: 'd_2', displayName: 'B', author: '', internalRelPath: '');

       var docs = await db.getAllDocs();
       expect(docs.length, 2);

       await db.deleteDocById('d_1');

       docs = await db.getAllDocs();
       expect(docs.length, 1);
       expect(docs.first.id, 'd_2');
    });
  });
}
