import '../models/tdl_event.dart';

class EventFilter {
  static final EventFilter _instance = EventFilter._internal();
  factory EventFilter() => _instance;
  EventFilter._internal();

  final Map<InteractionType, String> _lastEmittedContent = {};
  final Map<InteractionType, DateTime> _lastEmittedTime = {};

  bool shouldFilter(TdlEvent event) {
    // Standard conversational messages are not deduplicated
    if (event.type == InteractionType.conversation || event.type == InteractionType.system) {
      return false;
    }

    final String? lastContent = _lastEmittedContent[event.type];
    final DateTime? lastTime = _lastEmittedTime[event.type];

    // Suppress repetitive descriptions within an 8-second window
    if (lastContent != null && lastContent == event.content && lastTime != null) {
      final elapsed = DateTime.now().difference(lastTime);
      if (elapsed < const Duration(seconds: 8)) {
        print("🛡️ [EventFilter] Filtered repetitive context event: \"${event.content}\"");
        return true;
      }
    }

    _lastEmittedContent[event.type] = event.content;
    _lastEmittedTime[event.type] = DateTime.now();
    return false;
  }

  void clear() {
    _lastEmittedContent.clear();
    _lastEmittedTime.clear();
  }
}
