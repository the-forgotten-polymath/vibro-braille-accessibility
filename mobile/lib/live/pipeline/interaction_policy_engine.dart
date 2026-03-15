import '../models/tdl_event.dart';

class InteractionPolicyEngine {
  static final InteractionPolicyEngine _instance = InteractionPolicyEngine._internal();
  factory InteractionPolicyEngine() => _instance;
  InteractionPolicyEngine._internal();

  bool shouldPreempt(TdlEvent incoming, TdlEvent? active) {
    if (active == null) return true;
    
    // Safety critical events (e.g. hazards) always preempt general streams
    if (incoming.priority > active.priority) {
      return true;
    }
    return false;
  }

  bool isExpired(TdlEvent event) {
    final age = DateTime.now().difference(event.timestamp);
    return age > event.expiry;
  }

  bool isInterruptible(TdlEvent event) {
    // Safety critical events or hazard alerts cannot be interrupted by conversation
    if (event.type == InteractionType.hazard) {
      return false;
    }
    return true;
  }
}
