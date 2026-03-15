import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'socket_client/socket_manager.dart';

class VisionSenseScreen extends StatefulWidget {
  final SocketManager socketManager;
  const VisionSenseScreen({super.key, required this.socketManager});

  @override
  State<VisionSenseScreen> createState() => _VisionSenseScreenState();
}

class _VisionSenseScreenState extends State<VisionSenseScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  String _lastAnalysis = "Scanning environment...";
  Timer? _analysisTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
    try {
      await _controller!.initialize();
      setState(() {});
      // Start periodic analysis
      _analysisTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!_isProcessing) _captureAndAnalyze();
      });
    } catch (e) {
      print("Camera Error: $e");
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastAnalysis = "Capturing frame...";
    });

    try {
      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      if (widget.socketManager.sessionId != null) {
        widget.socketManager.sendVisionFrame(base64Image);
        setState(() => _lastAnalysis = "Analyzing environment...");
      } else {
        setState(() => _lastAnalysis = "Error: Not connected");
      }
    } catch (e) {
      print("Analysis Error: $e");
      setState(() => _lastAnalysis = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("VisionSense Mode", style: TextStyle(color: Colors.cyan)),
        actions: [
          IconButton(
            icon: Icon(_isProcessing ? Icons.sync : Icons.camera_alt, color: Colors.cyan),
            onPressed: _captureAndAnalyze,
          )
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),
          // HUD Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent, Colors.black.withOpacity(0.7)],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyan.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(_isProcessing ? Icons.auto_awesome : Icons.remove_red_eye, color: Colors.cyan),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _lastAnalysis,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Point camera at text or surroundings.\nSummary will be sent as haptic feedback.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
