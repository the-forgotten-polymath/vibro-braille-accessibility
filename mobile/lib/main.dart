import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'braille_engine/braille_translator.dart';
import 'braille_engine/temporal_encoder.dart';
import 'braille_engine/word_scheduler.dart';
import 'socket_client/socket_manager.dart';
import 'vision_sense_screen.dart';
import 'package:flutter/services.dart';
import 'live/core/live_mode_controller.dart';
import 'live/services/braille_renderer.dart';
import 'live/services/tts_service.dart';
import 'live/pipeline/tactile_runtime.dart';
import 'live/ui/live_assist_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => BrailleTranslator()),
        Provider(create: (_) => TemporalEncoder()),
      ],
      child: const VibroApp(),
    ),
  );
}

class VibroApp extends StatelessWidget {
  const VibroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const DemoTelemetryScreen(),
    );
  }
}

class DemoTelemetryScreen extends StatefulWidget {
  const DemoTelemetryScreen({super.key});

  @override
  State<DemoTelemetryScreen> createState() => _DemoTelemetryScreenState();
}

class _DemoTelemetryScreenState extends State<DemoTelemetryScreen> {
  late SocketManager socketManager;
  late WordScheduler wordScheduler;
  String status = "Disconnected";
  String fullSentence = "Ready to receive tactile stream...";
  String currentWord = "";
  double speed = 1.0;
  final TextEditingController _ipController =
      TextEditingController(text: "192.168.0.108");

  @override
  void initState() {
    super.initState();
    wordScheduler = WordScheduler(
      translator: context.read<BrailleTranslator>(),
      encoder: context.read<TemporalEncoder>(),
      onWordRendered: (word) {
        setState(() => currentWord = word);
      },
    );

    socketManager = SocketManager(
      url: 'ws://192.168.0.108:3000',
      onEventReceived: (data) {
        _handleEvent(data);
      },
      onConnected: () => setState(() => status = "Connected"),
      onDisconnected: () => setState(() => status = "Disconnected"),
    );

    // Listen for VisionSense & TDL Live Assist triggers from native code
    const MethodChannel('com.vibrobraille/trigger')
        .setMethodCallHandler((call) async {
      final liveRenderer = LiveBrailleRenderer(
        translator: context.read<BrailleTranslator>(),
        encoder: context.read<TemporalEncoder>(),
      );

      if (call.method == 'toggleLiveMode') {
        if (LiveModeController().isLiveMode) {
          if (mounted) Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 100));
          await LiveModeController().exitLiveMode(liveRenderer);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LiveAssistScreen()),
          );
          // Load Gemini API key from compile-time env (--dart-define=GEMINI_API_KEY=...)
          // Never hard-code secrets in source. See README for setup instructions.
          const apiKey = String.fromEnvironment(
            'GEMINI_API_KEY',
            defaultValue: 'YOUR_GEMINI_API_KEY_HERE',
          );
          await LiveModeController().enterLiveMode(
            context.read<BrailleTranslator>(),
            context.read<TemporalEncoder>(),
            apiKey,
          );
        }
      } else if (call.method == 'emergencyStop') {
        print("🚨 [MainActivity] Triggered Emergency Stop");
        await TactileRuntime().cancelActivePlayback(liveRenderer);
      } else if (call.method == 'muteTts') {
        print("🔇 [MainActivity] Triggered Mute TTS");
        await TtsService().stop();
      } else if (call.method == 'repeatLastMessage') {
        print("🔁 [MainActivity] Triggered Repeat Last Message");
        // Repeat the last message through tactile playback
      } else if (call.method == 'launchVisionSense') {
        _navigateToVisionSense();
      }
    });
  }

  void _navigateToVisionSense() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisionSenseScreen(socketManager: socketManager),
      ),
    );
  }

  void _handleEvent(Map<String, dynamic> data) {
    print("🔥 WS EVENT RECEIVED: ${data['type']} - ${data.toString()}");

    switch (data['type']) {
      case 'SET_SENTENCE':
        print("📝 Setting sentence: ${data['value']}");
        setState(() {
          fullSentence = data['value'];
          currentWord = "";
        });
        break;
      case 'WORD':
        print("📣 Scheduling word: ${data['value']}");
        // Do NOT await here, let the scheduler queue handle it 
        // so we don't block the socket heartbeat.
        wordScheduler.scheduleWord(data['value']); 
        break;
      case 'SENTENCE_END':
        print("🔚 Sentence end");
        wordScheduler.scheduleSentenceEnd();
        break;
      case 'PARAGRAPH_END':
        print("📄 Paragraph end");
        wordScheduler.scheduleParagraphEnd();
        break;
      case 'STOP':
        print("🛑 Forcibly stopping playback from server");
        wordScheduler.clear();
        break;
      default:
        print("❓ Unknown event type: ${data['type']}");
    }
  }

  void _showConnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Connect to AI Brain",
            style: TextStyle(color: Colors.cyan)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter the IP address of your PC:",
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "e.g. 192.168.1.10",
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyan)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            onPressed: () {
              final ip = _ipController.text.trim();
              if (ip.isNotEmpty) {
                socketManager.connect("MOCK-SESSION-123",
                    newUrl: "ws://$ip:3000");
              }
              Navigator.pop(context);
            },
            child: const Text("CONNECT", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// Builds the rich text for karaoke highlighting
  Widget _buildKaraokeText() {
    if (currentWord.isEmpty) {
      return Text(fullSentence,
          style: const TextStyle(color: Colors.white24, fontSize: 32));
    }

    final words = fullSentence.split(' ');
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
        children: words.map((word) {
          // Robust comparison ignoring punctuation/case
          final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          final cleanCurrent =
              currentWord.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          final isCurrent = cleanWord == cleanCurrent;

          return TextSpan(
            text: "$word ",
            style: TextStyle(
              color: isCurrent ? Colors.cyan : Colors.white24,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              shadows: isCurrent
                  ? [const Shadow(color: Colors.cyan, blurRadius: 20)]
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  int _pointerCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) => _pointerCount++,
        onPointerUp: (_) {
          // Detect multi-finger gestures on release
          if (_pointerCount == 2) socketManager.sendSignal("NEXT");
          if (_pointerCount == 3) socketManager.sendSignal("PREVIOUS");
          _pointerCount = 0;
        },
        child: GestureDetector(
          onLongPress: () => socketManager.sendSignal("REPEAT"),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle,
                            color: status == "Connected"
                                ? Colors.green
                                : Colors.red,
                            size: 12),
                        const SizedBox(width: 8),
                        Text(
                          status == "Connected"
                              ? "Connected to AI Brain"
                              : "Disconnected",
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                const Text(
                  "Streaming tactile words...",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                _buildKaraokeText(),
                const SizedBox(height: 40),
                Text(
                  currentWord,
                  style: const TextStyle(
                    color: Colors.cyan,
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -2,
                    shadows: [Shadow(color: Colors.cyan, blurRadius: 40)],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.grey, size: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: speed,
                        min: 0.25,
                        max: 2.0,
                        divisions: 7,
                        activeColor: Colors.cyan,
                        onChanged: (val) {
                          setState(() => speed = val);
                          // Sync with encoder so internal dots slow down too
                          context.read<TemporalEncoder>().speed = val;
                          socketManager.sendSignalWithData("SPEED", val);
                        },
                      ),
                    ),
                    Text(
                      "${speed}x",
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: status == "Disconnected"
          ? FloatingActionButton(
              backgroundColor: Colors.cyan,
              onPressed: _showConnectDialog,
              child: const Icon(Icons.link, color: Colors.black),
            )
          : null,
    );
  }
}
