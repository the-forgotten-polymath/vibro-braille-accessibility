import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/state.dart';
import '../models/tdl_event.dart';
import '../core/event_bus.dart';
import '../pipeline/gemini_stream_adapter.dart';
import '../pipeline/chunk_builder.dart';
import '../services/tts_service.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  WebSocketChannel? _channel;
  LiveSessionState _state = LiveSessionState.disconnected;
  StreamSubscription? _wsSubscription;
  StreamSubscription<TdlEvent>? _eventBusSubscription;
  Timer? _mockTimer;

  LiveSessionState get state => _state;
  final _stateController = StreamController<LiveSessionState>.broadcast();
  Stream<LiveSessionState> get stateStream => _stateController.stream;

  void _updateState(LiveSessionState newState) {
    _state = newState;
    _stateController.add(newState);
    print("🔌 [SessionManager] State transitioned: $_state");
  }

  Future<void> connect(String apiKey) async {
    if (_state != LiveSessionState.disconnected) return;
    _updateState(LiveSessionState.connecting);

    // Bidi WebSocket connection endpoint for Gemini Multimodal Live API
    final String url =
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$apiKey';

    print("🔌 [SessionManager] Connecting to: $url");

    try {
      // Use dart:io WebSocket directly — properly throws HTTP 401/403 errors
      // unlike web_socket_channel which silently converts them to onDone.
      final io.WebSocket rawSocket = await io.WebSocket.connect(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print("❌ [SessionManager] Handshake timeout after 15s");
          throw TimeoutException("Handshake timeout");
        },
      );

      print("✅ [SessionManager] WebSocket connected! readyState: ${rawSocket.readyState}");
      TtsService().speak("Gemini connected successfully");

      // Log close code and reason
      rawSocket.done.then((_) {
        print("🔌 [SessionManager] rawSocket done callback triggered.");
        print("🔌 [SessionManager] Close Code: ${rawSocket.closeCode}");
        print("🔌 [SessionManager] Close Reason: ${rawSocket.closeReason}");
      });

      // Wrap in web_socket_channel for compatibility with rest of code
      _channel = IOWebSocketChannel(rawSocket);
      _updateState(LiveSessionState.initializing);

      // Send initial Setup Config payload per Gemini Live API WebSocket spec:
      // using camelCase keys
      final setupMsg = {
        "setup": {
          "model": "models/gemini-2.0-flash-live-001",
          "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
              "voiceConfig": {
                "prebuiltVoiceConfig": {
                  "voiceName": "Puck"
                }
              }
            }
          },
          "systemInstruction": {
            "parts": [
              {
                "text":
                    "You are the real-time visual and voice assistant for VibroBraille, a device for visually impaired users. "
                    "Every streamed response must begin with a category tag prefix matching the content: "
                    "If pointing out a danger, obstacle, or drop: start with '[HAZARD]' followed by a single sentence description. "
                    "If providing a direction or guiding the user: start with '[GUIDANCE]' followed by a single sentence. "
                    "If reading text or signs: start with '[OCR]'. "
                    "If conversing generally: start with '[CONVERSATION]' followed by the sentence. "
                    "Keep each statement extremely concise (maximum 10-12 words). Respond in English."
              }
            ]
          }
        }
      };

      print("📤 [SessionManager] Sending setup: ${jsonEncode(setupMsg)}");
      _channel!.sink.add(jsonEncode(setupMsg));
      _updateState(LiveSessionState.streaming);

      // Send a minimal greeting text input to verify if connection remains open
      final initGreeting = {
        "clientContent": {
          "turns": [
            {
              "role": "user",
              "parts": [
                {"text": "Hello, session started."}
              ]
            }
          ],
          "turnComplete": true
        }
      };
      print("📤 [SessionManager] Sending initial greeting: ${jsonEncode(initGreeting)}");
      _channel!.sink.add(jsonEncode(initGreeting));

      // Listen to incoming messages from the server
      _wsSubscription = _channel!.stream.listen((message) {
        String decoded;
        if (message is List<int>) {
          decoded = utf8.decode(message);
        } else {
          decoded = message.toString();
        }
        print("📨 [SessionManager] RAW SERVER MSG: $decoded");
        GeminiStreamAdapter().handleServerMessage(decoded);
      }, onError: (e, stack) {
        final errMsg = e.toString();
        print("❌ [SessionManager] WebSocket stream error: $errMsg");
        print("❌ [SessionManager] Stack: $stack");
        TtsService().speak("Gemini stream error. $errMsg");
        disconnect();
      }, onDone: () {
        print("🔌 [SessionManager] WebSocket connection closed by server. Activating demo fallback.");
        // Server closed immediately — likely auth issue. Start fallback demo.
        _channel = null;
        _wsSubscription = null;
        _updateState(LiveSessionState.disconnected);
        TtsService().speak("Live mode demo.");
        _startMockSession();
      });

      // Listen to EventBus for outgoing camera frames and mic audio chunks
      _eventBusSubscription = EventBus().stream.listen((event) {
        if (_state != LiveSessionState.streaming) return;
        if (_channel == null) return; // Fallback/mock mode — no WebSocket to send to

        if (event.source == EventSource.camera) {
          // Stream camera frames per updated Live API spec: realtimeInput.video
          final frameInput = {
            "realtimeInput": {
              "video": {
                "data": event.content,
                "mimeType": "image/jpeg"
              }
            }
          };
          _channel!.sink.add(jsonEncode(frameInput));
        } else if (event.source == EventSource.user) {
          // Stream mic audio chunks per updated Live API spec: realtimeInput.audio
          final audioInput = {
            "realtimeInput": {
              "audio": {
                "data": event.content,
                "mimeType": "audio/pcm;rate=16000"
              }
            }
          };
          _channel!.sink.add(jsonEncode(audioInput));
        }
      });

    } catch (e, stack) {
      final errMsg = e.toString();
      print("❌ [SessionManager] Connection failed: $errMsg");
      print("❌ [SessionManager] Stack trace: $stack");
      // Connection failed — activate demo fallback immediately
      TtsService().speak("Demo mode.");
      _startMockSession();
    }
  }

  void _startMockSession() {
    _updateState(LiveSessionState.streaming);

    final mockOutputs = [
      "[GUIDANCE] Google DeepMind Hackathon.",
      "[OCR] Screen detected.",
      "[HAZARD] Person detected.",
      "[GUIDANCE] Turn left.",
    ];

    int counter = 0;
    _mockTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_state != LiveSessionState.streaming) {
        timer.cancel();
        return;
      }
      final msg = mockOutputs[counter % mockOutputs.length];
      counter++;

      final mockJson = jsonEncode({
        "serverContent": {
          "modelTurn": {
            "parts": [
              {"text": msg}
            ]
          }
        }
      });
      print("🎭 [SessionManager] Emitting Mock Live Token: \"$msg\"");
      GeminiStreamAdapter().handleServerMessage(mockJson);
    });
  }

  void disconnect() {
    if (_state == LiveSessionState.disconnected) return;
    _updateState(LiveSessionState.disconnected);

    _wsSubscription?.cancel();
    _wsSubscription = null;

    _eventBusSubscription?.cancel();
    _eventBusSubscription = null;

    _channel?.sink.close();
    _channel = null;

    _mockTimer?.cancel();
    _mockTimer = null;

    ChunkBuilder().clear();
  }
}
