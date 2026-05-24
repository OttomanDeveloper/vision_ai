import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

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
  VisionResult? _latestResult;
  StreamSubscription<VisionResult>? _subscription;

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
      _subscription = _vision.results.listen((result) {
        if (mounted) setState(() => _latestResult = result);
      });
      setState(() {
        _textureId = textureId;
        _isStarting = false;
      });
    } catch (e) {
      setState(() {
        _latestResult = null;
        _isStarting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _vision.stop();
    setState(() {
      _textureId = null;
      _latestResult = null;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _vision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _latestResult;
    final hand = result?.primaryHand;
    final face = result?.primaryFace;

    return Scaffold(
      appBar: AppBar(title: const Text('Vision AI — Combined Demo')),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            child: _textureId != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Texture(textureId: _textureId!),
                      if (hand != null)
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                hand.gesture == Gesture.custom
                                    ? (hand.customGestureName ?? 'CUSTOM').toUpperCase()
                                    : _gestureDisplayName(hand.gesture),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (face != null && face.emotion.isRecognized)
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _emotionDisplayName(face.emotion),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : const Center(
                    child: Text(
                      'Tap Start to begin camera',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
          ),

          // Info panel
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black87,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result != null) ...[
                  Text(
                    'Gesture: ${hand != null ? _gestureDisplayName(hand.gesture) : "No hand"}'
                    '${hand != null ? " (${(hand.gestureConfidence * 100).toStringAsFixed(0)}%)" : ""}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emotion: ${face != null && face.emotion.isRecognized ? _emotionDisplayName(face.emotion) : "No face"}'
                    '${face != null && face.emotion.isRecognized ? " (${(face.emotionConfidence * 100).toStringAsFixed(0)}%)" : ""}',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hands: ${result.hands.length} | Faces: ${result.faces.length} | '
                    '${result.inferenceTimeMs}ms',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  if (hand != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Fingers: ${_fingerStateString(hand.fingerStates)} | '
                      '${hand.isLeftHand ? "Left" : "Right"} hand',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ] else
                  const Text(
                    'Waiting for detection...',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
              ],
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _vision.isRunning ? null : _start,
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

  String _gestureDisplayName(Gesture gesture) => switch (gesture) {
        Gesture.fist => 'FIST ✊',
        Gesture.openHand => 'OPEN HAND ✋',
        Gesture.peace => 'PEACE ✌️',
        Gesture.thumbsUp => 'THUMBS UP 👍',
        Gesture.thumbsDown => 'THUMBS DOWN 👎',
        Gesture.pointingUp => 'POINTING ☝️',
        Gesture.ok => 'OK 👌',
        Gesture.iLoveYou => 'I LOVE YOU 🤟',
        Gesture.one => 'ONE 1️⃣',
        Gesture.two => 'TWO 2️⃣',
        Gesture.three => 'THREE 3️⃣',
        Gesture.four => 'FOUR 4️⃣',
        Gesture.five => 'FIVE 5️⃣',
        Gesture.custom => 'CUSTOM',
        Gesture.none => 'NONE',
      };

  String _emotionDisplayName(Emotion emotion) => switch (emotion) {
        Emotion.happy => 'HAPPY 😊',
        Emotion.sad => 'SAD 😢',
        Emotion.angry => 'ANGRY 😠',
        Emotion.surprised => 'SURPRISED 😮',
        Emotion.disgusted => 'DISGUSTED 🤢',
        Emotion.fearful => 'FEARFUL 😨',
        Emotion.neutral => 'NEUTRAL 😐',
        Emotion.none => 'NONE',
      };

  String _fingerStateString(Map<Finger, FingerState> states) {
    final labels = {
      Finger.thumb: 'T',
      Finger.indexFinger: 'I',
      Finger.middle: 'M',
      Finger.ring: 'R',
      Finger.pinky: 'P',
    };
    return states.entries.map((e) {
      final label = labels[e.key] ?? '?';
      final icon = e.value == FingerState.extended ? '↑' : '↓';
      return '$label$icon';
    }).join(' ');
  }
}
