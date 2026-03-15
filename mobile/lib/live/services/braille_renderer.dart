import 'package:flutter/services.dart';
import '../../braille_engine/braille_renderer_interface.dart';
import '../../braille_engine/braille_translator.dart';
import '../../braille_engine/temporal_encoder.dart';
import 'tts_service.dart';

class LiveBrailleRenderer implements BrailleRenderable {
  final BrailleTranslator translator;
  final TemporalEncoder encoder;
  static const platform = MethodChannel('com.vibrobraille/haptics');
  Future<void>? _activeSequence;
  bool _isCancelled = false;

  LiveBrailleRenderer({
    required this.translator,
    required this.encoder,
  });

  @override
  Future<void> render(String text, {int startWordIndex = 0, Function(int wordIdx)? onWordRendered, bool speakWords = true}) async {
    _isCancelled = false;
    final previousSequence = _activeSequence;
    
    final completer = Future.microtask(() async {
      await previousSequence;
      if (_isCancelled) return;

      final words = text.split(RegExp(r'\s+'));
      for (int w = startWordIndex; w < words.length; w++) {
        if (_isCancelled) return;
        final word = words[w];
        if (word.isEmpty) continue;

        // Notify caller of current word index progress for checkpointing
        if (onWordRendered != null) {
          onWordRendered(w);
        }

        // 1. Speak the word first if enabled
        if (speakWords) {
          await TtsService().speak(word);
        }

        final dotsPerChar = translator.translate(word);
        print("👁️ [LiveBrailleRenderer] Rendering word \"$word\" at index $w");

        // 2. Loop through characters of the word and render haptics
        for (int i = 0; i < dotsPerChar.length; i++) {
          if (_isCancelled) return;
          final dots = dotsPerChar[i];
          final pattern = encoder.encodeCharacter(dots);

          try {
            await platform.invokeMethod('vibrateWaveform', {
              'timings': pattern.timings,
              'amplitudes': pattern.amplitudes,
            });
            final charDuration = pattern.timings.fold(0, (sum, t) => sum + t);
            await Future.delayed(Duration(milliseconds: charDuration));
          } catch (e) {
            print("❌ [LiveBrailleRenderer] Waveform render error: $e");
          }
        }
      }
    });

    _activeSequence = completer;
    await completer;
  }

  @override
  Future<void> clear() async {
    print("🧹 [LiveBrailleRenderer] Clearing haptic queue");
    _isCancelled = true;
    _activeSequence = null;
    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': [1],
        'amplitudes': [0],
      });
    } catch (e) {
      print("❌ [LiveBrailleRenderer] Platform cancel error: $e");
    }
  }

  /// Plays a custom haptic checkpoint vibration pattern
  Future<void> playCheckpoint(List<int> timings, List<int> amplitudes) async {
    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': timings,
        'amplitudes': amplitudes,
      });
      final duration = timings.fold(0, (sum, t) => sum + t);
      await Future.delayed(Duration(milliseconds: duration));
    } catch (e) {
      print("❌ [LiveBrailleRenderer] Checkpoint error: $e");
    }
  }
}
