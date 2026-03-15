import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Plays raw PCM audio chunks streamed back from the Gemini Live API.
/// Gemini sends audio/pcm;rate=24000 base64-encoded chunks.
/// We collect chunks until turnComplete, write a WAV file and play it.
class GeminiAudioPlayer {
  static final GeminiAudioPlayer _instance = GeminiAudioPlayer._internal();
  factory GeminiAudioPlayer() => _instance;
  GeminiAudioPlayer._internal();

  final AudioPlayer _player = AudioPlayer();
  final List<Uint8List> _chunks = [];

  static const int _sampleRate = 24000;
  static const int _numChannels = 1;
  static const int _bitsPerSample = 16;

  /// Add a raw PCM chunk (already decoded from base64 by the adapter).
  void addChunk(Uint8List pcmBytes) {
    _chunks.add(pcmBytes);
    print("🔊 [GeminiAudioPlayer] Buffered PCM chunk: ${pcmBytes.length} bytes (total chunks: ${_chunks.length})");
  }

  /// Called when Gemini signals turnComplete. Assembles WAV and plays it.
  Future<void> playAndClear() async {
    if (_chunks.isEmpty) {
      print("🔊 [GeminiAudioPlayer] No audio chunks to play.");
      return;
    }

    // Concatenate all PCM chunks
    final int totalBytes = _chunks.fold(0, (sum, c) => sum + c.length);
    final Uint8List rawPcm = Uint8List(totalBytes);
    int offset = 0;
    for (final chunk in _chunks) {
      rawPcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _chunks.clear();

    print("🔊 [GeminiAudioPlayer] Assembling WAV: $totalBytes PCM bytes, ${_sampleRate}Hz, ${_numChannels}ch, ${_bitsPerSample}bit");

    // Build WAV file in memory
    final Uint8List wavBytes = _buildWav(rawPcm);

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gemini_response.wav');
      await file.writeAsBytes(wavBytes);

      print("🔊 [GeminiAudioPlayer] Playing WAV: ${file.path} (${wavBytes.length} bytes)");
      await _player.stop();
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      print("❌ [GeminiAudioPlayer] Playback error: $e");
    }
  }

  /// Stop and clear any currently playing audio + buffered chunks.
  Future<void> stop() async {
    _chunks.clear();
    await _player.stop();
  }

  /// Builds a valid 16-bit PCM WAV byte array from raw PCM data.
  Uint8List _buildWav(Uint8List pcmData) {
    final int byteRate = _sampleRate * _numChannels * (_bitsPerSample ~/ 8);
    final int blockAlign = _numChannels * (_bitsPerSample ~/ 8);
    final int dataSize = pcmData.length;
    final int chunkSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM = 16)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (PCM = 1)
    header.setUint16(22, _numChannels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmData);
    return wav;
  }
}
