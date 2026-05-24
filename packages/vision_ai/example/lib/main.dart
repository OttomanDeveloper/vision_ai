import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';
import 'package:vision_ai_flutter/vision_ai_flutter.dart';

void main() {
  runApp(const VisionAiExampleApp());
}

class VisionAiExampleApp extends StatelessWidget {
  const VisionAiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision AI Demo',
      theme: ThemeData.dark(),
      home: const CameraPage(),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final VisionAi _vision;
  int? _textureId;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _vision = VisionAi(
      hand: HandConfig(
        maxHands: 2,
        customGestures: [
          CustomGesture(
            name: 'rock',
            fingerStates: {
              Finger.thumb: FingerState.closed,
              Finger.indexFinger: FingerState.extended,
              Finger.middle: FingerState.closed,
              Finger.ring: FingerState.closed,
              Finger.pinky: FingerState.extended,
            },
          ),
        ],
      ),
      face: const FaceConfig(detectEmotion: true),
      camera: const CameraConfig(facing: CameraFacing.front),
    );
  }

  Future<void> _start() async {
    if (_isStarting || _vision.isRunning) return;
    setState(() => _isStarting = true);

    try {
      final textureId = await _vision.start();
      setState(() {
        _textureId = textureId;
        _isStarting = false;
      });
    } catch (e) {
      setState(() => _isStarting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    await _vision.stop();
    setState(() => _textureId = null);
  }

  @override
  void dispose() {
    _vision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vision AI')),
      body: Column(
        children: [
          Expanded(
            child: _textureId != null
                ? VisionAiCameraView(
                    controller: _vision,
                    textureId: _textureId!,
                    showHandLandmarks: true,
                    showFaceBoundingBox: true,
                    showGestureLabel: true,
                    showEmotionLabel: true,
                    style: const OverlayStyle(
                      handLandmark: LandmarkStyle(
                        dotColor: Colors.red,
                        lineColor: Colors.green,
                        dotRadius: 5.0,
                        lineWidth: 3.0,
                      ),
                      gestureLabel: LabelStyle(
                        fontSize: 28,
                        backgroundColor: Colors.black87,
                      ),
                      emotionLabel: LabelStyle(
                        fontSize: 22,
                        backgroundColor: Colors.blueAccent,
                      ),
                    ),
                    overlayBuilder: (context, result) {
                      return Positioned(
                        bottom: 60,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${result.inferenceTimeMs}ms',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Hands: ${result.hands.length} | Faces: ${result.faces.length}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Text(
                      'Tap Start to begin',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: (_vision.isRunning || _isStarting) ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_isStarting ? 'Starting...' : 'Start'),
                ),
                ElevatedButton.icon(
                  onPressed: _vision.isRunning ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
