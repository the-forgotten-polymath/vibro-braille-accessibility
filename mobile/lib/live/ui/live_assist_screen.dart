import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../core/live_mode_controller.dart';
import '../core/session_manager.dart';
import '../core/goal_tracker.dart';
import '../models/state.dart';
import '../services/camera_service.dart';
import '../services/braille_renderer.dart';
import '../../braille_engine/braille_translator.dart';
import '../../braille_engine/temporal_encoder.dart';
import 'package:provider/provider.dart';

class LiveAssistScreen extends StatefulWidget {
  const LiveAssistScreen({super.key});

  @override
  State<LiveAssistScreen> createState() => _LiveAssistScreenState();
}

class _LiveAssistScreenState extends State<LiveAssistScreen> {
  late LiveBrailleRenderer _renderer;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _renderer = LiveBrailleRenderer(
      translator: context.read<BrailleTranslator>(),
      encoder: context.read<TemporalEncoder>(),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    await CameraService().initialize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraController = CameraService().controller;
    final isInitialized = !_exiting && cameraController != null && CameraService().isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "V4 LIVE ASSIST",
          style: TextStyle(
            color: Color(0xFF22D3EE),
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.cyan),
            onPressed: () async {
              setState(() {
                _exiting = true;
              });
              await LiveModeController().exitLiveMode(_renderer);
              if (mounted) Navigator.pop(context);
            },
          )
        ],
      ),
      body: Stack(
        children: [
          // Glowing HUD layout & Camera preview
          if (isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: cameraController.value.aspectRatio,
                child: RotatedBox(
                  quarterTurns: 1, // Rotates 90 degrees clockwise to align portrait upright
                  child: CameraPreview(cameraController),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.cyan),
            ),

          // Diagnostic HUD Overlays
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // Telemetry and TDL diagnostic values
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Goal tracker status widget
                StreamBuilder(
                  stream: SessionManager().stateStream,
                  builder: (context, snapshot) {
                    final statusText = SessionManager().state.toString().split('.').last.toUpperCase();
                    final activeGoal = GoalTracker().activeGoal?.description ?? "NONE (General Ingest)";
                    
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.85),
                        border: Border.all(color: const Color(0xFF1E293B)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: SessionManager().state == LiveSessionState.streaming
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                      boxShadow: [
                                        BoxShadow(
                                          color: SessionManager().state == LiveSessionState.streaming
                                              ? const Color(0xFF10B981).withOpacity(0.5)
                                              : const Color(0xFFEF4444).withOpacity(0.5),
                                          blurRadius: 8,
                                        )
                                      ]
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "STATUS: $statusText",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                "LATENCY: ~340ms",
                                style: TextStyle(color: Colors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                          const Divider(color: Color(0xFF334155), height: 20),
                          Text(
                            "ACTIVE INTENT / GOAL:",
                            style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeGoal,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }
                ),
                const SizedBox(height: 16),
                const Text(
                  "Accessibility mode enabled.\nDouble press Volume Up to return to Reading Mode.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
