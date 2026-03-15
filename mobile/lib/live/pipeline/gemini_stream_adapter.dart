import 'dart:convert';
import 'dart:typed_data';
import '../core/event_bus.dart';
import '../models/tdl_event.dart';
import '../services/gemini_audio_player.dart';
import 'chunk_builder.dart';

class GeminiStreamAdapter {
  void handleServerMessage(String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      // ── Output Transcription (text alongside AUDIO modality) ──────────────
      // When responseModalities=AUDIO, the server may still send a text
      // transcription so we can feed haptic Braille.
      final outputTrans = data['outputTranscription'] ?? data['output_transcription'];
      if (outputTrans != null) {
        String? txt;
        if (outputTrans is String) {
          txt = outputTrans;
        } else if (outputTrans is Map) {
          if (outputTrans['text'] != null) {
            txt = outputTrans['text'].toString();
          } else if (outputTrans['parts'] != null) {
            final parts = outputTrans['parts'];
            if (parts is List) {
              final buf = StringBuffer();
              for (var p in parts) {
                if (p is Map && p['text'] != null) {
                  buf.write(p['text']);
                }
              }
              txt = buf.toString();
            }
          }
        }
        if (txt != null && txt.isNotEmpty) {
          print("📝 [GeminiStreamAdapter] Transcription: $txt");
          final turnId = data['serverContent']?['turnId'] ?? data['turnId'] ?? DateTime.now().millisecondsSinceEpoch;
          ChunkBuilder().addToken(txt, 'trans-$turnId');
        }
      }

      // ── Server Content (model turn) ───────────────────────────────────────
      final serverContent = data['serverContent'];
      if (serverContent != null) {
        final modelTurn = serverContent['modelTurn'];
        if (modelTurn != null && modelTurn['parts'] != null) {
          for (var part in modelTurn['parts']) {

            // ── TEXT part (when modality=TEXT or alongside AUDIO) ──────────
            final text = part['text'];
            if (text != null && text.toString().isNotEmpty) {
              print("📝 [GeminiStreamAdapter] Text part: $text");
              final responseId = 'turn-${serverContent['turnId'] ?? DateTime.now().millisecondsSinceEpoch}';
              ChunkBuilder().addToken(text.toString(), responseId);
            }

            // ── AUDIO inlineData (when modality=AUDIO) ────────────────────
            final inlineData = part['inlineData'];
            if (inlineData != null) {
              final mimeType = inlineData['mimeType']?.toString() ?? '';
              final rawData  = inlineData['data']?.toString() ?? '';
              if (mimeType.startsWith('audio/') && rawData.isNotEmpty) {
                print("🔊 [GeminiStreamAdapter] Audio chunk received, mimeType: $mimeType, base64 len: ${rawData.length}");
                try {
                  final Uint8List pcmBytes = base64Decode(rawData);
                  GeminiAudioPlayer().addChunk(pcmBytes);
                } catch (e) {
                  print("❌ [GeminiStreamAdapter] Failed to decode audio base64: $e");
                }
              }
            }
          }
        }

        // ── Turn complete: flush remaining text tokens + play buffered audio ─
        if (serverContent['turnComplete'] == true) {
          print("✅ [GeminiStreamAdapter] Turn complete. Flushing text + playing audio.");
          ChunkBuilder().forceEmitRemaining();
          // Play all buffered PCM chunks as one WAV
          GeminiAudioPlayer().playAndClear();

          EventBus().publish(TdlEvent(
            id: 'gemini-tc-${DateTime.now().millisecondsSinceEpoch}',
            timestamp: DateTime.now(),
            source: EventSource.gemini,
            type: InteractionType.system,
            status: EventStatus.stable,
            priority: 10,
            content: '[TURN_COMPLETE]',
          ));
        }

        // ── Model interrupted ─────────────────────────────────────────────
        if (serverContent['interrupted'] == true) {
          print("⚠️ [GeminiStreamAdapter] Turn interrupted by server.");
          GeminiAudioPlayer().stop();
          EventBus().publish(TdlEvent(
            id: 'gemini-int-${DateTime.now().millisecondsSinceEpoch}',
            timestamp: DateTime.now(),
            source: EventSource.gemini,
            type: InteractionType.system,
            status: EventStatus.interrupted,
            priority: 100,
            content: '[INTERRUPTED]',
          ));
        }
      }
    } catch (e, stack) {
      print("❌ [GeminiStreamAdapter] Error parsing WebSocket frame: $e");
      print("❌ [GeminiStreamAdapter] Stack: $stack");
    }
  }
}
