enum EventSource {
  gemini,
  camera,
  user,
  system,
}

enum InteractionType {
  conversation,
  guidance,
  hazard,
  ocr,
  system,
}

enum EventStatus {
  partial,
  stable,
  interrupted,
  expired,
}

class TdlEvent {
  final String id;
  final DateTime timestamp;
  final EventSource source;
  final InteractionType type;
  final EventStatus status;
  final int priority;
  final String content;
  final Duration expiry;

  TdlEvent({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.type,
    required this.status,
    required this.priority,
    required this.content,
    this.expiry = const Duration(seconds: 10),
  });

  TdlEvent copyWith({
    String? id,
    DateTime? timestamp,
    EventSource? source,
    InteractionType? type,
    EventStatus? status,
    int? priority,
    String? content,
    Duration? expiry,
  }) {
    return TdlEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      type: type ?? this.type,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      content: content ?? this.content,
      expiry: expiry ?? this.expiry,
    );
  }

  @override
  String toString() {
    return 'TdlEvent(id: $id, type: $type, status: $status, priority: $priority, content: $content)';
  }
}
