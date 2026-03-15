class Hazard {
  final String objectType;
  final double distance; // meters
  final String direction; // e.g. "left", "center", "right"
  final int priority;

  Hazard({
    required this.objectType,
    required this.distance,
    required this.direction,
    required this.priority,
  });
}
