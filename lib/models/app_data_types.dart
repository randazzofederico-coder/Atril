enum FileSystemItemType { folder, file }

class FileSystemItem {
  final String id;
  final String name;
  final FileSystemItemType type;
  final String path; // Ruta completa o relativa

  FileSystemItem({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
  });

  bool get isDirectory => type == FileSystemItemType.folder;
}