class UserIntent {
  final String rawUtterance;
  final String actionType; // e.g. "search", "navigate", "read", "chat"
  final Map<String, dynamic> slots; // e.g. {"target": "chair"}

  UserIntent({
    required this.rawUtterance,
    required this.actionType,
    required this.slots,
  });
}
