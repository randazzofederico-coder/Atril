class Setlist {
  /// Stable identifier for referencing this setlist across the app (and future DB).
  final String setlistId;

  /// Display name.
  final String name;

  /// Ordered list of docIds (order is the order).
  final List<String> docIds;

  const Setlist({
    required this.setlistId,
    required this.name,
    required this.docIds,
  });
}
