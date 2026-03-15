import 'dart:async';
import 'package:flutter/services.dart';
import '../core/event_bus.dart';
import '../models/tdl_event.dart';

class MicService {
  static final MicService _instance = MicService._internal();
  factory MicService() => _instance;
  MicService._internal() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "audioChunk") {
        final String base64Audio = call.arguments as String;
        if (_isRecording) {
          // Publish real mic audio chunk event to EventBus
          EventBus().publish(TdlEvent(
            id: 'mic-${DateTime.now().millisecondsSinceEpoch}',
            timestamp: DateTime.now(),
            source: EventSource.user,
            type: InteractionType.system,
            status: EventStatus.partial,
            priority: 1,
            content: base64Audio,
          ));
        }
      }
    });
  }

  static const _channel = MethodChannel('com.vibrobraille/mic');
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> initialize() async {
    print("🎙️ [MicService] Initializing microphone");
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    _isRecording = true;
    print("🎙️ [MicService] Starting mic audio stream (PCM 16kHz Mono)");
    try {
      await _channel.invokeMethod('startRecording');
    } catch (e) {
      print("❌ [MicService] Failed to start native recording: $e");
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    print("🎙️ [MicService] Stopping mic audio stream");
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (e) {
      print("❌ [MicService] Failed to stop native recording: $e");
    }
  }

  void dispose() {
    stopRecording();
  }
}
