class SetlistNavContext {
  final String setlistId;
  final int index; // 0-based
  final int total;

  const SetlistNavContext({
    required this.setlistId,
    required this.index,
    required this.total,
  });
}