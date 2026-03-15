import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import '../core/event_bus.dart';
import '../models/tdl_event.dart';

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  Timer? _frameTimer;
  double _fps = 0.25; // Default slow rate (1 frame every 4 seconds) to avoid thread lock and autofocus pulses
  bool _isCapturing = false;
  bool _isProcessingFrame = false;

  double get fps => _fps;
  bool get isCapturing => _isCapturing;

  bool get isInitialized {
    try {
      return _controller != null && _controller!.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    int retries = 3;
    while (retries > 0) {
      try {
        if (_controller != null) {
          if (isInitialized) return;
          final oldCtrl = _controller;
          _controller = null;
          try {
            await oldCtrl?.dispose();
          } catch (e) {
            print("⚠️ [CameraService] Error disposing old controller during re-init: $e");
          }
        }
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          print("⚠️ [CameraService] No cameras found.");
          return;
        }
        _controller = CameraController(
          cameras[0],
          ResolutionPreset.low, // Lower resolution for fast payloads
          enableAudio: false,
        );
        await _controller!.initialize();
        
        // Explicitly turn off flash to avoid blinking on proximity
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (e) {
          print("⚠️ [CameraService] Failed to set flash mode: $e");
        }
        print("📹 [CameraService] Camera initialized successfully");
        return; // Success! Exit loop
      } catch (e) {
        retries--;
        print("❌ [CameraService] Camera initialization failed (retries left: $retries): $e");
        if (retries > 0) {
          await Future.delayed(const Duration(milliseconds: 800)); // Wait for hardware locks to release
        }
      }
    }
  }

  CameraController? get controller => _controller;

  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    print("📹 [CameraService] Starting capture at $_fps FPS");
    _scheduleFrameTimer();
  }

  void stopCapture() {
    if (!_isCapturing) return;
    _isCapturing = false;
    print("📹 [CameraService] Stopping capture");
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  void updateFps(double newFps) {
    if (newFps <= 0) return;
    if (newFps == _fps) return;
    print("📹 [CameraService] Updating FPS from $_fps to $newFps");
    _fps = newFps;
    if (_isCapturing) {
      _frameTimer?.cancel();
      _scheduleFrameTimer();
    }
  }

  void _scheduleFrameTimer() {
    final intervalMs = (1000 / _fps).round();
    _frameTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!_isProcessingFrame && _isCapturing) {
        _captureAndEmit();
      }
    });
  }

  Future<void> _captureAndEmit() async {
    if (!_isCapturing) return;
    final ctrl = _controller;
    if (ctrl == null || !isInitialized) return;
    
    _isProcessingFrame = true;
    try {
      final XFile image = await ctrl.takePicture();
      
      // Guard: If capture was stopped while takePicture was asynchronously executing, abort
      if (!_isCapturing || _controller == null) {
        print("📹 [CameraService] Capture stopped during execution. Aborting publish.");
        return;
      }

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      // Publish camera event to the EventBus
      EventBus().publish(TdlEvent(
        id: 'cam-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        source: EventSource.camera,
        type: InteractionType.system,
        status: EventStatus.stable,
        priority: 5,
        content: base64Image,
      ));
    } catch (e) {
      print("❌ [CameraService] Frame capture failed: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> dispose() async {
    stopCapture();
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (e) {
        print("⚠️ [CameraService] Error disposing controller: $e");
      }
    }
  }
}
