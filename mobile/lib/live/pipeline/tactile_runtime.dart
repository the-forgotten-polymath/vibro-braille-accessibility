import 'dart:async';
import '../core/event_bus.dart';
import '../core/output_arbiter.dart';
import '../models/tdl_event.dart';
import '../services/braille_renderer.dart';
import '../services/tts_service.dart';
import 'event_filter.dart';
import 'interaction_policy_engine.dart';
import 'revision_manager.dart';

import '../core/task_manager.dart';
import '../models/preemptable_task.dart';

class TactileRuntime {
  static final TactileRuntime _instance = TactileRuntime._internal();
  factory TactileRuntime() => _instance;
  TactileRuntime._internal();

  StreamSubscription<TdlEvent>? _subscription;
  bool _isExecuting = false;

  void start(LiveBrailleRenderer brailleRenderer) {
    if (_subscription != null) return;
    print("🧠 [TactileRuntime] Initializing and starting TDL Event Listener");

    _subscription = EventBus().stream.listen((event) async {
      // Filter out outgoing sensor inputs (camera frames, mic audio) from TDL flow
      if (event.source == EventSource.camera || event.source == EventSource.user) {
        return;
      }

      // Handle direct user voice/interruption events
      if (event.status == EventStatus.interrupted || event.content == '[INTERRUPTED]') {
        print("🧠 [TactileRuntime] Interruption Event received. Clearing task stack.");
        RevisionManager().triggerInterruption();
        TaskManager().clearAll();
        await cancelActivePlayback(brailleRenderer);
        return;
      }

      // Verify event validity against RevisionManager
      if (!RevisionManager().isEventValid(event.id, 0)) {
        return;
      }

      // Filter duplicate/repetitive context events
      if (EventFilter().shouldFilter(event)) {
        return;
      }

      // Create a preemptable task representation
      final newTask = PreemptableTask(
        id: event.id,
        type: event.type,
        priority: event.priority,
        content: event.content,
      );

      // Push task to TaskManager and check if we should preempt the current runner
      final didPreempt = TaskManager().pushTask(newTask);
      if (didPreempt) {
        await cancelActivePlayback(brailleRenderer);
        _runTaskLoop(brailleRenderer);
      }
    });
  }

  Future<void> cancelActivePlayback(LiveBrailleRenderer brailleRenderer) async {
    await brailleRenderer.clear();
    await TtsService().stop();
  }

  Future<void> _runTaskLoop(LiveBrailleRenderer brailleRenderer) async {
    if (_isExecuting) return;
    _isExecuting = true;

    try {
      while (TaskManager().activeTask != null) {
        final current = TaskManager().activeTask!;
        print("🧠 [TactileRuntime] Executing task: ${current.id} from checkpoint wordIndex: ${current.wordIndex}");

        // 1. Query Arbiter for channels
        final channels = OutputArbiter().route(current.type);

        // 2. Playback based on route
        if (channels.contains(OutputChannel.audio) && !channels.contains(OutputChannel.haptic)) {
          // Speak whole text (audio-only task)
          await TtsService().speak(current.content);
          // Audio-only TTS needs to wait for completion so it doesn't immediately skip or clip
          await Future.delayed(Duration(milliseconds: current.content.split(' ').length * 350 + 200));
        } else if (channels.contains(OutputChannel.haptic)) {
          // Play haptics (+ speech inside renderer per-word) from the saved checkpoint
          await brailleRenderer.render(
            current.content,
            startWordIndex: current.wordIndex,
            onWordRendered: (wordIdx) {
              current.wordIndex = wordIdx; // Keep checkpoint index up to date
            },
            speakWords: channels.contains(OutputChannel.audio), // Only speak per-word if Audio channel is enabled
          );
        }

        // If the task was not paused (i.e. not pre-empted by a new incoming task), it is complete
        if (current.status != TaskStatus.paused) {
          TaskManager().completeActiveTask();
        } else {
          // Task was pre-empted; break loop to let the new higher priority task start fresh
          print("🧠 [TactileRuntime] Task ${current.id} was paused mid-execution. Suspending loop.");
          break;
        }
      }
    } finally {
      _isExecuting = false;
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    TaskManager().clearAll();
  }
}
