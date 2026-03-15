import '../models/tdl_event.dart';

enum OutputChannel {
  audio,
  haptic,
}

class OutputArbiter {
  static final OutputArbiter _instance = OutputArbiter._internal();
  factory OutputArbiter() => _instance;
  OutputArbiter._internal();

  List<OutputChannel> route(InteractionType type) {
    switch (type) {
      case InteractionType.hazard:
        // Safety critical alerts must trigger both speech and haptic vibration
        return [OutputChannel.audio, OutputChannel.haptic];
      case InteractionType.guidance:
        // Navigation directions get both
        return [OutputChannel.audio, OutputChannel.haptic];
      case InteractionType.ocr:
        // OCR text gets tactile haptics only to preserve private reading
        return [OutputChannel.haptic];
      case InteractionType.system:
        // Mode changes / status cues are haptic only
        return [OutputChannel.haptic];
      case InteractionType.conversation:
      default:
        // Standard chat is directed to TTS speech only to protect tactile bandwidth
        return [OutputChannel.audio];
    }
  }
}
