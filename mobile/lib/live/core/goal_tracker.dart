import '../models/goal.dart';

class GoalTracker {
  static final GoalTracker _instance = GoalTracker._internal();
  factory GoalTracker() => _instance;
  GoalTracker._internal();

  Goal? _activeGoal;

  Goal? get activeGoal => _activeGoal;

  void startGoal(String description, Map<String, dynamic> criteria) {
    _activeGoal = Goal(
      id: 'goal-${DateTime.now().millisecondsSinceEpoch}',
      description: description,
      isCompleted: false,
      criteria: criteria,
    );
    print("🏆 [GoalTracker] Persistent goal started: \"$description\"");
  }

  void completeGoal() {
    if (_activeGoal != null) {
      _activeGoal = _activeGoal!.copyWith(isCompleted: true);
      print("🏆 [GoalTracker] Persistent goal achieved: \"${_activeGoal!.description}\"");
      _activeGoal = null;
    }
  }

  void clearGoal() {
    _activeGoal = null;
  }
}
