class Score {
  /// Stable identifier for referencing this document across the app (and future DB).
  final String docId;

  /// Display metadata (editable in future).
  final String title;
  final String author;

  /// Source PDF path (MVP). Future: internal storage path / uri.
  final String? filePath;

  /// Carpeta lógica donde se encuentra (filesystem tree).
  /// Por defecto es 'root'.
  final String folderId;

  const Score({
    required this.docId,
    required this.title,
    required this.author,
    this.filePath,
    this.folderId = 'root',
  });
}