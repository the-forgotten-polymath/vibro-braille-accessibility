import '../services/braille_renderer.dart';

class BrailleScheduler {
  final LiveBrailleRenderer renderer;

  BrailleScheduler({required this.renderer});

  Future<void> scheduleText(String text) async {
    // Delegates to the modally independent LiveBrailleRenderer
    await renderer.render(text);
  }

  Future<void> cancelAll() async {
    await renderer.clear();
  }
}
