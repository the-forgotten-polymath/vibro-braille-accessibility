import '../models/tdl_event.dart';
import '../core/event_bus.dart';

class ChunkBuilder {
  static final ChunkBuilder _instance = ChunkBuilder._internal();
  factory ChunkBuilder() => _instance;
  ChunkBuilder._internal();

  final StringBuffer _buffer = StringBuffer();
  String _currentResponseId = "";

  void addToken(String token, String responseId) {
    if (_currentResponseId != responseId) {
      _currentResponseId = responseId;
      _buffer.clear();
    }
    _buffer.write(token);
    _checkAndEmitStableChunks();
  }

  void _checkAndEmitStableChunks() {
    final text = _buffer.toString();
    // Match clauses ending with period, question mark, exclamation, or newline
    final RegExp sentenceRegex = RegExp(r'([^.!?\n]+[.!?\n]+)');
    final Iterable<RegExpMatch> matches = sentenceRegex.allMatches(text);

    if (matches.isNotEmpty) {
      int lastMatchEnd = 0;
      for (final match in matches) {
        final clause = match.group(0)!.trim();
        if (clause.isNotEmpty) {
          _emitEvent(clause);
        }
        lastMatchEnd = match.end;
      }
      final remaining = text.substring(lastMatchEnd);
      _buffer.clear();
      _buffer.write(remaining);
    }
  }

  void forceEmitRemaining() {
    final text = _buffer.toString().trim();
    if (text.isNotEmpty) {
      _emitEvent(text);
    }
    _buffer.clear();
  }

  void clear() {
    _buffer.clear();
    _currentResponseId = "";
  }

  void _emitEvent(String clause) {
    InteractionType type = InteractionType.conversation;
    String content = clause;

    // Detect structured system prefix prompts
    if (clause.toUpperCase().startsWith('[HAZARD]')) {
      type = InteractionType.hazard;
      content = clause.substring(8).trim();
    } else if (clause.toUpperCase().startsWith('[GUIDANCE]')) {
      type = InteractionType.guidance;
      content = clause.substring(10).trim();
    } else if (clause.toUpperCase().startsWith('[OCR]')) {
      type = InteractionType.ocr;
      content = clause.substring(5).trim();
    } else if (clause.toUpperCase().startsWith('[SYSTEM]')) {
      type = InteractionType.system;
      content = clause.substring(8).trim();
    } else if (clause.toUpperCase().startsWith('[CONVERSATION]')) {
      type = InteractionType.conversation;
      content = clause.substring(14).trim();
    }

    final event = TdlEvent(
      id: 'chunk-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      source: EventSource.gemini,
      type: type,
      status: EventStatus.stable,
      priority: _getPriorityForType(type),
      content: content,
    );

    print("🧩 [ChunkBuilder] Built stable clause: \"$content\" [Type: $type]");
    EventBus().publish(event);
  }

  int _getPriorityForType(InteractionType type) {
    switch (type) {
      case InteractionType.hazard:
        return 90;
      case InteractionType.guidance:
        return 80;
      case InteractionType.ocr:
        return 50;
      case InteractionType.system:
        return 10;
      case InteractionType.conversation:
      default:
        return 20;
    }
  }
}
