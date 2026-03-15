import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketManager {
  String url;
  String? sessionId;
  WebSocketChannel? _channel;
  final Function(Map<String, dynamic>) onEventReceived;
  final Function() onConnected;
  final Function() onDisconnected;

  SocketManager({
    required this.url,
    required this.onEventReceived,
    required this.onConnected,
    required this.onDisconnected,
  });

  void connect(String sessionId, {String? newUrl}) async {
    this.sessionId = sessionId;
    if (newUrl != null) {
      url = newUrl;
    }
    if (_channel != null) {
      _channel!.sink.close();
    }

    try {
      print("🔌 CONNECTING TO: ${newUrl ?? url}");
      final uri = Uri.parse(newUrl ?? url);
      print("📍 Parsed URI: $uri");

      print("⏳ Attempting WebSocket connection...");
      _channel = WebSocketChannel.connect(uri);
      print("⏳ Waiting for channel readiness...");
      await _channel!.ready.timeout(const Duration(seconds: 5), onTimeout: () {
        print("❌ Handshake TIMEOUT after 5s");
        throw Exception("Handshake timeout");
      });
      print("✅ WebSocket READY");

      // Identify this device
      final identifyMsg =
          jsonEncode({'type': 'IDENTIFY', 'sessionId': sessionId});
      print("📤 Sending IDENTIFY: $identifyMsg");
      _channel!.sink.add(identifyMsg);
      print("✅ IDENTIFY sent");

      print("👂 Setting up stream listener...");
      _channel!.stream.listen(
        (message) {
          print("🌐 RAW WS MESSAGE: $message");
          try {
            final data = jsonDecode(message);
            print("✅ DECODED: ${data.toString()}");
            onEventReceived(data);
          } catch (e) {
            print("❌ WS Decode Error: $e");
          }
        },
        onDone: () {
          print("⚠️ WebSocket stream closed");
          onDisconnected();
        },
        onError: (e) {
          print("❌ WebSocket error: $e");
          onDisconnected();
        },
      );

      print("✅ Stream listener active");
      onConnected();
    } catch (e) {
      print("❌ Connection failed: $e");
      onDisconnected();
    }
  }

  void sendSignal(String signal) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'SIGNAL',
        'signal': signal,
      }));
    }
  }

  void sendSignalWithData(String signal, dynamic value) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'SIGNAL',
        'signal': signal,
        'value': value,
      }));
    }
  }

  void sendVisionFrame(String base64Frame) {
    if (_channel != null && sessionId != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'VISION_FRAME',
        'sessionId': sessionId,
        'frame': base64Frame,
      }));
    }
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
