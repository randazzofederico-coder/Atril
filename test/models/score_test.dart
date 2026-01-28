import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_setlist/models/score.dart';

void main() {
  group('Score Model Tests', () {
    test('Score should be instantiated correctly with mandatory fields', () {
      const score = Score(
        docId: 'd_123',
        title: 'Mi Partitura',
        author: 'Beethoven',
      );

      expect(score.docId, 'd_123');
      expect(score.title, 'Mi Partitura');
      expect(score.author, 'Beethoven');
      expect(score.filePath, null);
      expect(score.folderId, 'root'); // Valor por defecto
    });

    test('Score should accept optional fields', () {
      const score = Score(
        docId: 'd_456',
        title: 'Otra Partitura',
        author: 'Bach',
        filePath: '/path/to/file.pdf',
        folderId: 'f_789',
      );

      expect(score.filePath, '/path/to/file.pdf');
      expect(score.folderId, 'f_789');
    });
  });
}
