import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'braille_translator.dart';
import 'temporal_encoder.dart';
import 'braille_renderer_interface.dart';

class WordScheduler implements BrailleRenderable {
  final BrailleTranslator translator;
  final TemporalEncoder encoder;
  final Function(String) onWordRendered;
  final FlutterTts tts = FlutterTts();

  static const platform = MethodChannel('com.vibrobraille/haptics');
  Future<void>? _activeSequence;

  WordScheduler({
    required this.translator,
    required this.encoder,
    required this.onWordRendered,
  }) {
    _initTts();
  }

  @override
  Future<void> render(String text) async {
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.isNotEmpty) {
        await scheduleWord(word);
      }
    }
  }

  @override
  Future<void> clear() async {
    _activeSequence = null;
    try {
      await platform.invokeMethod('vibrateWaveform', {
        'timings': [1],
        'amplitudes': [0],
      });
    } on PlatformException catch (e) {
      print("Haptic clear error: ${e.message}");
    }
  }

  /// Helper to queue haptic sequences so they don't overlap.
  Future<void> _queueSequence(Future<void> Function() action) async {
    final previousSequence = _activeSequence;
    final completer = Future.microtask(() async {
      await previousSequence;
      await action();
    });
    _activeSequence = completer;
    await completer;
  }

  void _initTts() async {
    await tts.setLanguage("en-US");
    await tts.setSpeechRate(0.5);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
  }

  /// Processes a single word: translates, encodes one alphabet at a time, and vibrates.
  Future<void> scheduleWord(String word) async {
    await _queueSequence(() async {
      try {
        onWordRendered(word);
        tts.speak(word);

        final dotsPerChar = translator.translate(word);
        
        print("🔍 WORD: $word");
        print("🔍 Dots length: ${dotsPerChar.length}, Word length: ${word.length}");

        // Loop through the translated characters
        for (int i = 0; i < dotsPerChar.length; i++) {
          try {
            final dots = dotsPerChar[i];
            final char = (i < word.length) ? word[i] : '?';
            
            final pattern = encoder.encodeCharacter(dots);

            print("🌊 Vibrating alphabet: '$char' (${i + 1}/${dotsPerChar.length})");

            await platform.invokeMethod('vibrateWaveform', {
              'timings': pattern.timings,
              'amplitudes': pattern.amplitudes,
            });

            final charDuration = pattern.timings.fold(0, (sum, t) => sum + t);
            await Future.delayed(Duration(milliseconds: charDuration));
          } catch (charError) {
            print("❌ Error at alphabet index $i ($word): $charError");
          }
        }
      } catch (wordError) {
        print("❌ Critical error in scheduleWord ($word): $wordError");
      }
    });
  }

  /// Long buzz for sentence end (~700ms).
  Future<void> scheduleSentenceEnd() async {
    await _queueSequence(() async {
      try {
        await platform.invokeMethod('vibrateWaveform', {
          'timings': [700],
          'amplitudes': [255],
        });
        await Future.delayed(const Duration(milliseconds: 700));
      } on PlatformException catch (e) {
        print("Haptic error: ${e.message}");
      }
    });
  }

  /// Double long buzz for paragraph end.
  Future<void> scheduleParagraphEnd() async {
    await _queueSequence(() async {
      try {
        await platform.invokeMethod('vibrateWaveform', {
          'timings': [500, 200, 500],
          'amplitudes': [255, 0, 255],
        });
        await Future.delayed(const Duration(milliseconds: 1200));
      } on PlatformException catch (e) {
        print("Haptic error: ${e.message}");
      }
    });
  }
}
