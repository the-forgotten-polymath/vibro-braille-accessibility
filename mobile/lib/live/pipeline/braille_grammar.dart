import '../models/tdl_event.dart';

class BrailleGrammar {
  static final BrailleGrammar _instance = BrailleGrammar._internal();
  factory BrailleGrammar() => _instance;
  BrailleGrammar._internal();

  List<int>? getCheckpointTimings(InteractionType type) {
    switch (type) {
      case InteractionType.hazard:
        return [150, 50, 150]; // Double warning pulse
      case InteractionType.guidance:
        return [100, 50, 100]; // Guidance navigation alert
      case InteractionType.ocr:
        return [80]; // OCR tap
      case InteractionType.system:
        return [200, 100, 200]; // System pairing/mode double long pulse
      default:
        return null;
    }
  }

  List<int>? getCheckpointAmplitudes(InteractionType type) {
    switch (type) {
      case InteractionType.hazard:
        return [255, 0, 255];
      case InteractionType.guidance:
        return [180, 0, 180];
      case InteractionType.ocr:
        return [120];
      case InteractionType.system:
        return [255, 0, 255];
      default:
        return null;
    }
  }
}
