import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.55);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      print("❌ [TtsService] Error: $msg");
    });
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    print("🗣️ [TtsService] Speaking: \"$text\"");
    await _tts.speak(text);
  }

  Future<void> stop() async {
    if (!_isSpeaking) return;
    print("🗣️ [TtsService] Stop / Interrupt speech");
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> updateSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }
}
