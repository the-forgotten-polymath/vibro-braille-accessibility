import '../../braille_engine/braille_translator.dart';
import '../../braille_engine/temporal_encoder.dart';
import '../pipeline/tactile_runtime.dart';
import '../services/braille_renderer.dart';
import '../services/camera_service.dart';
import '../services/mic_service.dart';
import '../services/tts_service.dart';
import 'session_manager.dart';

class LiveModeController {
  static final LiveModeController _instance = LiveModeController._internal();
  factory LiveModeController() => _instance;
  LiveModeController._internal();

  bool _isLiveMode = false;
  bool get isLiveMode => _isLiveMode;

  Future<void> enterLiveMode(
    BrailleTranslator translator,
    TemporalEncoder encoder,
    String apiKey,
  ) async {
    if (_isLiveMode) return;
    _isLiveMode = true;
    print("🚀 [LiveModeController] Entering Live Assist Mode (V4)");

    // Initialize capture and speech engines
    await TtsService().initialize();
    await CameraService().initialize();
    await MicService().initialize();

    // Setup live haptics renderer
    final liveRenderer = LiveBrailleRenderer(
      translator: translator,
      encoder: encoder,
    );

    // Start Tactile Decision Layer Event Listener
    TactileRuntime().start(liveRenderer);

    // Force-reset any lingering session state (e.g., leftover mock session)
    // before attempting a new Gemini connection.
    SessionManager().disconnect();

    // Establish bidirectional WebSocket session
    await SessionManager().connect(apiKey);

    // Trigger camera and microphone capture streams continuously
    CameraService().startCapture();
    MicService().startRecording();
  }

  Future<void> exitLiveMode(LiveBrailleRenderer liveRenderer) async {
    if (!_isLiveMode) return;
    _isLiveMode = false;
    print("🚀 [LiveModeController] Exiting Live Assist Mode. Returning to Reading Mode (V3)");

    // Stop and teardown sensor feeds
    CameraService().stopCapture();
    MicService().stopRecording();

    // Disconnect WS session
    SessionManager().disconnect();

    // Stop and clean playback queues
    await TactileRuntime().cancelActivePlayback(liveRenderer);
    TactileRuntime().stop();

    // Free resources
    await CameraService().dispose();
    MicService().dispose();
  }
}
