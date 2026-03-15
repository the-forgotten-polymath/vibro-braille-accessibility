import 'dart:async';
import '../models/tdl_event.dart';

class EventBus {
  // Singleton pattern
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _controller = StreamController<TdlEvent>.broadcast();

  Stream<TdlEvent> get stream => _controller.stream;

  void publish(TdlEvent event) {
    print("🚌 [EventBus] Publishing: $event");
    _controller.add(event);
  }

  Stream<TdlEvent> on<T extends TdlEvent>() {
    return _controller.stream;
  }

  void dispose() {
    // Note: Since EventBus is a singleton, typically we won't close it,
    // but useful for cleanup in testing or resets.
  }
}
