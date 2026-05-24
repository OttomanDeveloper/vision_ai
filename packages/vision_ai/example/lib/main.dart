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
  String _status = 'Tap Start to begin';
  int _frameCount = 0;
  StreamSubscription<VisionResult>? _subscription;

  @override
  void initState() {
    super.initState();
    _vision = VisionAi.hand(
      camera: const CameraConfig(facing: CameraFacing.front),
    );
  }

  Future<void> _start() async {
    if (_isStarting || _vision.isRunning) return;
    setState(() => _isStarting = true);

    try {
      final textureId = await _vision.start();
      _subscription = _vision.results.listen((result) {
        _frameCount++;
        if (mounted) {
          setState(() {
            _status = 'Frame #$_frameCount | '
                '${result.inferenceTimeMs}ms | '
                'Hands: ${result.hands.length} | '
                'Faces: ${result.faces.length}';
          });
        }
      });
      setState(() {
        _textureId = textureId;
        _isStarting = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isStarting = false;
      });
    }
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _vision.stop();
    setState(() {
      _textureId = null;
      _frameCount = 0;
      _status = 'Stopped';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Vision AI — Camera Test')),
      body: Column(
        children: [
          Expanded(
            child: _textureId != null
                ? Texture(textureId: _textureId!)
                : const Center(
                    child: Text(
                      'Camera preview will appear here',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            width: double.infinity,
            child: Text(
              _status,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
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
}
