class Folder {
  final String id;
  final String name;
  final String? parentId; // null o 'root' (o el ID de la carpeta padre)
  final int position;

  const Folder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.position,
  });
}