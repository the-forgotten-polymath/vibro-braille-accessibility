import 'dart:math';

class TouchPoint {
  final double x;
  final double y;
  final int id;

  TouchPoint(this.x, this.y, this.id);
}

class ClusteringAlgorithm {
  final double radiusThreshold;

  ClusteringAlgorithm({this.radiusThreshold = 50.0});

  /// Groups touch points that are within a certain radius to prevent "jitter" dots.
  /// Returns a map of Zone ID (1-6) to whether it's active.
  Map<int, bool> getActiveZones(List<TouchPoint> touches, Map<int, Point<double>> calibrationMap) {
    Map<int, bool> activeZones = {};
    
    for (var touch in touches) {
      for (var entry in calibrationMap.entries) {
        double dist = _distance(Point(touch.x, touch.y), entry.value);
        if (dist < radiusThreshold) {
          activeZones[entry.key] = true;
        }
      }
    }
    
    return activeZones;
  }

  double _distance(Point<double> p1, Point<double> p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }
}
