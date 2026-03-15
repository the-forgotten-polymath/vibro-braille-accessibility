import 'package:flutter_test/flutter_test.dart';
import 'package:vibrobraille_hybrid/live/models/tdl_event.dart';
import 'package:vibrobraille_hybrid/live/pipeline/chunk_builder.dart';
import 'package:vibrobraille_hybrid/live/pipeline/revision_manager.dart';
import 'package:vibrobraille_hybrid/live/pipeline/event_filter.dart';
import 'package:vibrobraille_hybrid/live/pipeline/interaction_policy_engine.dart';
import 'package:vibrobraille_hybrid/live/core/output_arbiter.dart';
import 'package:vibrobraille_hybrid/live/core/event_bus.dart';

void main() {
  group('TDL ChunkBuilder Tests', () {
    setUp(() {
      ChunkBuilder().clear();
    });

    test('Buffers tokens and emits stable sentence clause', () async {
      final List<TdlEvent> emittedEvents = [];
      final subscription = EventBus().stream.listen((event) {
        emittedEvents.add(event);
      });

      // Add incremental streaming tokens
      ChunkBuilder().addToken('[HAZARD] Obstacle', 'res-1');
      ChunkBuilder().addToken(' ahead', 'res-1');
      ChunkBuilder().addToken('. ', 'res-1'); // Trigger stable boundary

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(emittedEvents.length, equals(1));
      expect(emittedEvents.first.type, equals(InteractionType.hazard));
      expect(emittedEvents.first.content, equals('Obstacle ahead.'));
    });

    test('Categorizes standard conversation, guidance, and OCR correctly', () async {
      final List<TdlEvent> emittedEvents = [];
      final subscription = EventBus().stream.listen((event) {
        emittedEvents.add(event);
      });

      ChunkBuilder().addToken('[GUIDANCE] Turn left. ', 'res-2');
      ChunkBuilder().addToken('[OCR] Exit sign. ', 'res-2');
      ChunkBuilder().addToken('Hello there. ', 'res-2');

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(emittedEvents.length, equals(3));
      expect(emittedEvents[0].type, equals(InteractionType.guidance));
      expect(emittedEvents[0].content, equals('Turn left.'));
      expect(emittedEvents[1].type, equals(InteractionType.ocr));
      expect(emittedEvents[1].content, equals('Exit sign.'));
      expect(emittedEvents[2].type, equals(InteractionType.conversation));
      expect(emittedEvents[2].content, equals('Hello there.'));
    });
  });

  group('TDL RevisionManager Tests', () {
    test('Invalidates old response IDs on new response start', () {
      RevisionManager().startNewResponse('response-a');
      expect(RevisionManager().isEventValid('response-a', 0), isTrue);
      expect(RevisionManager().isEventValid('response-b', 0), isFalse);
    });

    test('Invalidates all response streams on interruption', () {
      RevisionManager().startNewResponse('response-a');
      RevisionManager().triggerInterruption();
      expect(RevisionManager().isEventValid('response-a', 0), isFalse);
    });
  });

  group('TDL EventFilter Spatial Memory Tests', () {
    setUp(() {
      EventFilter().clear();
    });

    test('Allows first guidance event but filters identical subsequent events within threshold', () {
      final event1 = TdlEvent(
        id: '1',
        timestamp: DateTime.now(),
        source: EventSource.gemini,
        type: InteractionType.guidance,
        status: EventStatus.stable,
        priority: 80,
        content: 'Chair on left',
      );

      final event2 = TdlEvent(
        id: '2',
        timestamp: DateTime.now(),
        source: EventSource.gemini,
        type: InteractionType.guidance,
        status: EventStatus.stable,
        priority: 80,
        content: 'Chair on left',
      );

      expect(EventFilter().shouldFilter(event1), isFalse); // First event passes
      expect(EventFilter().shouldFilter(event2), isTrue);  // Duplicate gets suppressed
    });
  });

  group('TDL InteractionPolicyEngine Tests', () {
    test('Preempts active lower priority events with higher priority events', () {
      final lowPriority = TdlEvent(
        id: '1',
        timestamp: DateTime.now(),
        source: EventSource.gemini,
        type: InteractionType.conversation,
        status: EventStatus.stable,
        priority: 20,
        content: 'Nice weather today',
      );

      final highPriority = TdlEvent(
        id: '2',
        timestamp: DateTime.now(),
        source: EventSource.gemini,
        type: InteractionType.hazard,
        status: EventStatus.stable,
        priority: 90,
        content: 'Obstacle ahead',
      );

      expect(InteractionPolicyEngine().shouldPreempt(highPriority, lowPriority), isTrue);
      expect(InteractionPolicyEngine().shouldPreempt(lowPriority, highPriority), isFalse);
    });
  });

  group('TDL OutputArbiter Tests', () {
    test('Routes hazard to both audio and haptic channels', () {
      final channels = OutputArbiter().route(InteractionType.hazard);
      expect(channels.contains(OutputChannel.audio), isTrue);
      expect(channels.contains(OutputChannel.haptic), isTrue);
    });

    test('Routes chat conversation to audio speech channel only', () {
      final channels = OutputArbiter().route(InteractionType.conversation);
      expect(channels.contains(OutputChannel.audio), isTrue);
      expect(channels.contains(OutputChannel.haptic), isFalse);
    });
  });
}
