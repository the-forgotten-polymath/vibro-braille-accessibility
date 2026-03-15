import '../models/intent.dart';

class IntentManager {
  static final IntentManager _instance = IntentManager._internal();
  factory IntentManager() => _instance;
  IntentManager._internal();

  UserIntent? _currentIntent;

  UserIntent? get currentIntent => _currentIntent;

  void updateIntent(String utterance, String action, Map<String, dynamic> slots) {
    _currentIntent = UserIntent(
      rawUtterance: utterance,
      actionType: action,
      slots: slots,
    );
    print("🎯 [IntentManager] Intent updated: $action | Slots: $slots");
  }

  void clearIntent() {
    _currentIntent = null;
  }
}
