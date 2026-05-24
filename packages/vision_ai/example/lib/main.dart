import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  VisionAi? _vision;
  int? _textureId;
  bool _isStarting = false;
  String? _permissionError;
  VisionResult? _latestResult;
  StreamSubscription<VisionResult>? _resultSub;

  // --- Tweakable settings ---
  bool _enableHand = true;
  bool _enableFace = true;
  bool _detectEmotion = true;
  bool _detectLandmarks = false;
  bool _detectContours = false;
  int _maxHands = 2;
  double _minDetectionConfidence = 0.5;
  bool _enableGestureFilter = false;
  double _minFaceSize = 0.1;
  bool _enableFaceTracking = true;
  bool _faceAccurateMode = false;
  CameraFacing _cameraFacing = CameraFacing.front;
  AnalysisResolution _resolution = AnalysisResolution.medium;
  int _maxResultsPerSecond = 0; // 0 = no throttle

  // --- Overlay toggles ---
  bool _showHandLandmarks = true;
  bool _showHandBoundingBox = false;
  bool _showFaceBoundingBox = true;
  bool _showFaceContours = false;
  bool _enableBlinkDetection = false;
  bool _enableHeadGesture = false;
  bool _enableFaceDistance = false;
  bool _enableAttentionScore = false;
  bool _showWorldCoords = false;
  bool _enableHandMotion = false;
  bool _enableTwoHandInteraction = false;
  BlinkDetector? _blinkDetector;
  HeadGestureDetector? _headGestureDetector;
  FaceDistanceEstimator? _distanceEstimator;
  AttentionScorer? _attentionScorer;
  HandMotionTracker? _handMotionTracker;
  TwoHandInteractionDetector? _twoHandDetector;
  BlinkEvent? _lastBlink;
  HeadGestureEvent? _lastHeadGesture;
  FaceDistanceEstimate? _lastDistance;
  AttentionScore? _lastAttention;
  HandMotion? _lastHandMotion;
  TwoHandEvent? _lastTwoHandEvent;
  bool _showGestureLabel = true;
  bool _showEmotionLabel = true;
  bool _showStats = true;

  VisionAi _createVision() {
    return VisionAi(
      hand: _enableHand
          ? HandConfig(
              maxHands: _maxHands,
              minDetectionConfidence: _minDetectionConfidence,
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
              deniedGestures: _enableGestureFilter
                  ? {Gesture.fist, Gesture.openHand}
                  : null,
              gestureThresholds: _enableGestureFilter
                  ? {Gesture.thumbsUp: 0.8, Gesture.peace: 0.7}
                  : null,
            )
          : null,
      face: _enableFace
          ? FaceConfig(
              detectEmotion: _detectEmotion,
              detectLandmarks: _detectLandmarks,
              detectContours: _detectContours,
              minFaceSize: _minFaceSize,
              enableTracking: _enableFaceTracking,
              accurateMode: _faceAccurateMode,
            )
          : null,
      camera: CameraConfig(
        facing: _cameraFacing,
        resolution: _resolution,
        maxResultsPerSecond: _maxResultsPerSecond,
      ),
    );
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied) {
      setState(() => _permissionError =
          'Camera permission permanently denied. Enable in Settings.');
    } else {
      setState(() => _permissionError = 'Camera permission is required.');
    }
    return false;
  }

  Future<void> _start() async {
    if (_isStarting || (_vision?.isRunning ?? false)) return;
    if (!_enableHand && !_enableFace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable at least hand or face detection')),
      );
      return;
    }

    setState(() {
      _isStarting = true;
      _permissionError = null;
    });

    if (!await _requestCameraPermission()) {
      setState(() => _isStarting = false);
      return;
    }

    try {
      _vision?.dispose();
      _vision = _createVision();
      final textureId = await _vision!.start();
      if (_enableBlinkDetection) _blinkDetector = BlinkDetector();
      if (_enableHeadGesture) _headGestureDetector = HeadGestureDetector();
      if (_enableFaceDistance) _distanceEstimator = FaceDistanceEstimator();
      if (_enableAttentionScore) _attentionScorer = AttentionScorer();
      if (_enableHandMotion) _handMotionTracker = HandMotionTracker();
      if (_enableTwoHandInteraction) {
        _twoHandDetector = TwoHandInteractionDetector();
      }
      _resultSub = _vision!.results.listen((r) {
        if (!mounted) return;
        BlinkEvent? blink;
        HeadGestureEvent? headGesture;
        final face = r.primaryFace;
        if (face != null) {
          if (_blinkDetector != null) {
            blink = _blinkDetector!.update(face, r.timestampMs);
          }
          if (_headGestureDetector != null) {
            headGesture = _headGestureDetector!.update(face, r.timestampMs);
          }
        }
        FaceDistanceEstimate? dist;
        if (_distanceEstimator != null && face != null) {
          dist = _distanceEstimator!.estimate(face, r.imageSize);
        }
        AttentionScore? attention;
        if (_attentionScorer != null && face != null) {
          attention = _attentionScorer!.update(face, r.timestampMs);
        }
        HandMotion? handMotion;
        final hand = r.primaryHand;
        if (_handMotionTracker != null && hand != null) {
          handMotion = _handMotionTracker!.update(hand, r.timestampMs);
        }
        TwoHandEvent? twoHandEvent;
        if (_twoHandDetector != null) {
          twoHandEvent = _twoHandDetector!.update(r);
        }
        setState(() {
          _latestResult = r;
          if (blink != null) _lastBlink = blink;
          if (headGesture != null) _lastHeadGesture = headGesture;
          if (dist != null) _lastDistance = dist;
          if (attention != null) _lastAttention = attention;
          if (handMotion != null) _lastHandMotion = handMotion;
          if (twoHandEvent != null) _lastTwoHandEvent = twoHandEvent;
        });
      });
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
    await _resultSub?.cancel();
    _resultSub = null;
    await _vision?.stop();
    _blinkDetector?.reset();
    _blinkDetector = null;
    _headGestureDetector?.reset();
    _headGestureDetector = null;
    _distanceEstimator = null;
    _attentionScorer?.reset();
    _attentionScorer = null;
    _handMotionTracker?.reset();
    _handMotionTracker = null;
    _twoHandDetector?.reset();
    _twoHandDetector = null;
    setState(() {
      _textureId = null;
      _latestResult = null;
      _lastBlink = null;
      _lastHeadGesture = null;
      _lastDistance = null;
      _lastAttention = null;
      _lastHandMotion = null;
      _lastTwoHandEvent = null;
    });
  }

  Future<void> _restart() async {
    await _stop();
    await _start();
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    _vision?.dispose();
    super.dispose();
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SettingsSheet(
        enableHand: _enableHand,
        enableFace: _enableFace,
        detectEmotion: _detectEmotion,
        detectLandmarks: _detectLandmarks,
        detectContours: _detectContours,
        enableBlinkDetection: _enableBlinkDetection,
        enableHeadGesture: _enableHeadGesture,
        enableFaceDistance: _enableFaceDistance,
        enableAttentionScore: _enableAttentionScore,
        enableHandMotion: _enableHandMotion,
        enableTwoHandInteraction: _enableTwoHandInteraction,
        maxHands: _maxHands,
        minDetectionConfidence: _minDetectionConfidence,
        enableGestureFilter: _enableGestureFilter,
        minFaceSize: _minFaceSize,
        enableFaceTracking: _enableFaceTracking,
        faceAccurateMode: _faceAccurateMode,
        cameraFacing: _cameraFacing,
        resolution: _resolution,
        maxResultsPerSecond: _maxResultsPerSecond,
        showHandLandmarks: _showHandLandmarks,
        showHandBoundingBox: _showHandBoundingBox,
        showFaceBoundingBox: _showFaceBoundingBox,
        showFaceContours: _showFaceContours,
        showGestureLabel: _showGestureLabel,
        showEmotionLabel: _showEmotionLabel,
        showStats: _showStats,
        showWorldCoords: _showWorldCoords,
        onChanged: (settings) {
          setState(() {
            _enableHand = settings.enableHand;
            _enableFace = settings.enableFace;
            _detectEmotion = settings.detectEmotion;
            _detectLandmarks = settings.detectLandmarks;
            _detectContours = settings.detectContours;
            _enableBlinkDetection = settings.enableBlinkDetection;
            _enableHeadGesture = settings.enableHeadGesture;
            _enableFaceDistance = settings.enableFaceDistance;
            _enableAttentionScore = settings.enableAttentionScore;
            _enableHandMotion = settings.enableHandMotion;
            _enableTwoHandInteraction = settings.enableTwoHandInteraction;
            _maxHands = settings.maxHands;
            _minDetectionConfidence = settings.minDetectionConfidence;
            _enableGestureFilter = settings.enableGestureFilter;
            _minFaceSize = settings.minFaceSize;
            _enableFaceTracking = settings.enableFaceTracking;
            _faceAccurateMode = settings.faceAccurateMode;
            _cameraFacing = settings.cameraFacing;
            _resolution = settings.resolution;
            _maxResultsPerSecond = settings.maxResultsPerSecond;
            _showHandLandmarks = settings.showHandLandmarks;
            _showHandBoundingBox = settings.showHandBoundingBox;
            _showFaceBoundingBox = settings.showFaceBoundingBox;
            _showFaceContours = settings.showFaceContours;
            _showGestureLabel = settings.showGestureLabel;
            _showEmotionLabel = settings.showEmotionLabel;
            _showStats = settings.showStats;
            _showWorldCoords = settings.showWorldCoords;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _vision?.isRunning ?? false;
    final result = _latestResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _textureId != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      VisionAiCameraView(
                        controller: _vision!,
                        textureId: _textureId!,
                        showHandLandmarks: _showHandLandmarks,
                        showHandBoundingBox: _showHandBoundingBox,
                        showFaceBoundingBox: _showFaceBoundingBox,
                        showFaceContours: _showFaceContours,
                        showGestureLabel: _showGestureLabel,
                        showEmotionLabel: _showEmotionLabel,
                      ),
                      if (_showStats && result != null)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: _StatsOverlay(result: result, lastBlink: _lastBlink, lastHeadGesture: _lastHeadGesture, lastDistance: _lastDistance, lastAttention: _lastAttention, lastHandMotion: _lastHandMotion, lastTwoHandEvent: _lastTwoHandEvent, showWorldCoords: _showWorldCoords),
                        ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, size: 64, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        const Text('Tap Start to begin',
                            style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          '${_enableHand ? "Hand" : ""}${_enableHand && _enableFace ? " + " : ""}${_enableFace ? "Face" : ""} detection',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                        if (_permissionError != null) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _permissionError!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          TextButton(
                            onPressed: () => openAppSettings(),
                            child: const Text('Open Settings'),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: (isRunning || _isStarting) ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_isStarting ? 'Starting...' : 'Start'),
                  ),
                  ElevatedButton.icon(
                    onPressed: isRunning ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                  if (isRunning)
                    ElevatedButton.icon(
                      onPressed: _restart,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Restart'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats overlay (bottom-right)
// ---------------------------------------------------------------------------
class _StatsOverlay extends StatelessWidget {
  final VisionResult result;
  final BlinkEvent? lastBlink;
  final HeadGestureEvent? lastHeadGesture;
  final FaceDistanceEstimate? lastDistance;
  final AttentionScore? lastAttention;
  final HandMotion? lastHandMotion;
  final TwoHandEvent? lastTwoHandEvent;
  final bool showWorldCoords;
  const _StatsOverlay({required this.result, this.lastBlink, this.lastHeadGesture, this.lastDistance, this.lastAttention, this.lastHandMotion, this.lastTwoHandEvent, this.showWorldCoords = false});

  @override
  Widget build(BuildContext context) {
    final hand = result.primaryHand;
    final face = result.primaryFace;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _line('Inference', '${result.inferenceTimeMs}ms'),
          _line('Hands', '${result.hands.length}'),
          _line('Faces', '${result.faces.length}'),
          if (hand != null) ...[
            _line('Gesture', _gestureName(hand.gesture)),
            _line('Confidence', '${(hand.gestureConfidence * 100).toStringAsFixed(0)}%'),
            _line('Side', hand.isLeftHand ? 'Left' : 'Right'),
            _line(
              'Fingers',
              [
                hand.fingerStates[Finger.thumb] == FingerState.extended ? 'T' : '',
                hand.fingerStates[Finger.indexFinger] == FingerState.extended ? 'I' : '',
                hand.fingerStates[Finger.middle] == FingerState.extended ? 'M' : '',
                hand.fingerStates[Finger.ring] == FingerState.extended ? 'R' : '',
                hand.fingerStates[Finger.pinky] == FingerState.extended ? 'P' : '',
              ].where((s) => s.isNotEmpty).join(''),
            ),
            if (showWorldCoords && hand.worldLandmarks.length >= 21) ...[
              _line('Pinch', '${(hand.worldLandmarks[HandLandmarkIndex.thumbTip].distanceTo(hand.worldLandmarks[HandLandmarkIndex.indexTip]) * 100).toStringAsFixed(1)}cm'),
              _line('Span', '${(hand.worldLandmarks[HandLandmarkIndex.thumbTip].distanceTo(hand.worldLandmarks[HandLandmarkIndex.pinkyTip]) * 100).toStringAsFixed(1)}cm'),
            ],
            if (lastHandMotion != null)
              _line('Motion', '${lastHandMotion!.state.name} ${lastHandMotion!.direction.name} (${lastHandMotion!.speed.toStringAsFixed(2)}/s)'),
          ],
          if (lastTwoHandEvent != null)
            _line('2-Hand', '${lastTwoHandEvent!.gesture.name} (d=${lastTwoHandEvent!.distance.toStringAsFixed(3)})'),
          if (face != null && face.emotion.isRecognized) ...[
            _line('Emotion', face.emotion.name),
            _line('Emotion %', '${(face.emotionConfidence * 100).toStringAsFixed(0)}%'),
            if (face.smilingProbability != null)
              _line('Smile', '${(face.smilingProbability! * 100).toStringAsFixed(0)}%'),
          ],
          if (lastBlink != null)
            _line('Blink', '${lastBlink!.eye.name} (${lastBlink!.durationMs}ms)'),
          if (lastHeadGesture != null)
            _line('Head', lastHeadGesture!.gesture == HeadGesture.nod ? 'YES (nod)' : 'NO (shake)'),
          if (lastDistance != null)
            _line('Distance', '${lastDistance!.distanceCm.toStringAsFixed(0)}cm (${lastDistance!.zone.name})'),
          if (lastAttention != null) ...[
            _line('Attention', '${(lastAttention!.score * 100).toStringAsFixed(0)}% (${lastAttention!.level.name})'),
            _line('  Eye', '${(lastAttention!.eyeScore * 100).toStringAsFixed(0)}%'),
            _line('  Orient', '${(lastAttention!.orientationScore * 100).toStringAsFixed(0)}%'),
            _line('  Stable', '${(lastAttention!.stabilityScore * 100).toStringAsFixed(0)}%'),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ',
                style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      );

  String _gestureName(Gesture g) => switch (g) {
        Gesture.fist => 'Fist',
        Gesture.openHand => 'Open',
        Gesture.peace => 'Peace',
        Gesture.thumbsUp => 'ThumbUp',
        Gesture.thumbsDown => 'ThumbDn',
        Gesture.pointingUp => 'Point',
        Gesture.ok => 'OK',
        Gesture.iLoveYou => 'ILY',
        Gesture.one => '1',
        Gesture.two => '2',
        Gesture.three => '3',
        Gesture.four => '4',
        Gesture.five => '5',
        Gesture.custom => 'Custom',
        Gesture.none => '-',
      };
}

// ---------------------------------------------------------------------------
// Settings data class
// ---------------------------------------------------------------------------
class _Settings {
  final bool enableHand;
  final bool enableFace;
  final bool detectEmotion;
  final int maxHands;
  final double minDetectionConfidence;
  final bool enableGestureFilter;
  final double minFaceSize;
  final bool enableFaceTracking;
  final bool faceAccurateMode;
  final bool detectLandmarks;
  final bool detectContours;
  final bool enableBlinkDetection;
  final bool enableHeadGesture;
  final bool enableFaceDistance;
  final bool enableAttentionScore;
  final bool enableHandMotion;
  final bool enableTwoHandInteraction;
  final CameraFacing cameraFacing;
  final AnalysisResolution resolution;
  final int maxResultsPerSecond;
  final bool showHandLandmarks;
  final bool showHandBoundingBox;
  final bool showFaceBoundingBox;
  final bool showFaceContours;
  final bool showGestureLabel;
  final bool showEmotionLabel;
  final bool showStats;
  final bool showWorldCoords;

  const _Settings({
    required this.enableHand,
    required this.enableFace,
    required this.detectEmotion,
    required this.detectLandmarks,
    required this.detectContours,
    required this.enableBlinkDetection,
    required this.enableHeadGesture,
    required this.enableFaceDistance,
    required this.enableAttentionScore,
    required this.enableHandMotion,
    required this.enableTwoHandInteraction,
    required this.maxHands,
    required this.minDetectionConfidence,
    required this.enableGestureFilter,
    required this.minFaceSize,
    required this.enableFaceTracking,
    required this.faceAccurateMode,
    required this.cameraFacing,
    required this.resolution,
    required this.maxResultsPerSecond,
    required this.showHandLandmarks,
    required this.showHandBoundingBox,
    required this.showFaceBoundingBox,
    required this.showFaceContours,
    required this.showGestureLabel,
    required this.showEmotionLabel,
    required this.showStats,
    required this.showWorldCoords,
  });
}

// ---------------------------------------------------------------------------
// Settings bottom sheet
// ---------------------------------------------------------------------------
class _SettingsSheet extends StatefulWidget {
  final bool enableHand;
  final bool enableFace;
  final bool detectEmotion;
  final bool detectLandmarks;
  final bool detectContours;
  final bool enableBlinkDetection;
  final bool enableHeadGesture;
  final bool enableFaceDistance;
  final bool enableAttentionScore;
  final bool enableHandMotion;
  final bool enableTwoHandInteraction;
  final int maxHands;
  final double minDetectionConfidence;
  final bool enableGestureFilter;
  final double minFaceSize;
  final bool enableFaceTracking;
  final bool faceAccurateMode;
  final CameraFacing cameraFacing;
  final AnalysisResolution resolution;
  final int maxResultsPerSecond;
  final bool showHandLandmarks;
  final bool showHandBoundingBox;
  final bool showFaceBoundingBox;
  final bool showFaceContours;
  final bool showGestureLabel;
  final bool showEmotionLabel;
  final bool showStats;
  final bool showWorldCoords;
  final ValueChanged<_Settings> onChanged;

  const _SettingsSheet({
    required this.enableHand,
    required this.enableFace,
    required this.detectEmotion,
    required this.detectLandmarks,
    required this.detectContours,
    required this.enableBlinkDetection,
    required this.enableHeadGesture,
    required this.enableFaceDistance,
    required this.enableAttentionScore,
    required this.enableHandMotion,
    required this.enableTwoHandInteraction,
    required this.maxHands,
    required this.minDetectionConfidence,
    required this.enableGestureFilter,
    required this.minFaceSize,
    required this.enableFaceTracking,
    required this.faceAccurateMode,
    required this.cameraFacing,
    required this.resolution,
    required this.maxResultsPerSecond,
    required this.showHandLandmarks,
    required this.showHandBoundingBox,
    required this.showFaceBoundingBox,
    required this.showFaceContours,
    required this.showGestureLabel,
    required this.showEmotionLabel,
    required this.showStats,
    required this.showWorldCoords,
    required this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _enableHand = widget.enableHand;
  late bool _enableFace = widget.enableFace;
  late bool _detectEmotion = widget.detectEmotion;
  late bool _detectLandmarks = widget.detectLandmarks;
  late bool _detectContours = widget.detectContours;
  late bool _blinkDetect = widget.enableBlinkDetection;
  late bool _headGesture = widget.enableHeadGesture;
  late bool _faceDistance = widget.enableFaceDistance;
  late bool _attentionScore = widget.enableAttentionScore;
  late bool _handMotion = widget.enableHandMotion;
  late bool _twoHandInteraction = widget.enableTwoHandInteraction;
  late int _maxHands = widget.maxHands;
  late double _minDetConf = widget.minDetectionConfidence;
  late bool _gestureFilter = widget.enableGestureFilter;
  late double _minFaceSize = widget.minFaceSize;
  late bool _faceTracking = widget.enableFaceTracking;
  late bool _accurateMode = widget.faceAccurateMode;
  late CameraFacing _facing = widget.cameraFacing;
  late AnalysisResolution _res = widget.resolution;
  late int _maxResults = widget.maxResultsPerSecond;
  late bool _showLandmarks = widget.showHandLandmarks;
  late bool _showHandBox = widget.showHandBoundingBox;
  late bool _showContours = widget.showFaceContours;
  late bool _showFaceBox = widget.showFaceBoundingBox;
  late bool _showGesture = widget.showGestureLabel;
  late bool _showEmotion = widget.showEmotionLabel;
  late bool _showStats = widget.showStats;
  late bool _showWorld = widget.showWorldCoords;

  void _emit() {
    widget.onChanged(_Settings(
      enableHand: _enableHand,
      enableFace: _enableFace,
      detectEmotion: _detectEmotion,
      detectLandmarks: _detectLandmarks,
      detectContours: _detectContours,
      enableBlinkDetection: _blinkDetect,
      enableHeadGesture: _headGesture,
      enableFaceDistance: _faceDistance,
      enableAttentionScore: _attentionScore,
      enableHandMotion: _handMotion,
      enableTwoHandInteraction: _twoHandInteraction,
      maxHands: _maxHands,
      minDetectionConfidence: _minDetConf,
      enableGestureFilter: _gestureFilter,
      minFaceSize: _minFaceSize,
      enableFaceTracking: _faceTracking,
      faceAccurateMode: _accurateMode,
      cameraFacing: _facing,
      resolution: _res,
      maxResultsPerSecond: _maxResults,
      showHandLandmarks: _showLandmarks,
      showHandBoundingBox: _showHandBox,
      showFaceBoundingBox: _showFaceBox,
      showFaceContours: _showContours,
      showGestureLabel: _showGesture,
      showEmotionLabel: _showEmotion,
      showStats: _showStats,
      showWorldCoords: _showWorld,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('DETECTION', style: _sectionStyle),
          const SizedBox(height: 8),
          _toggle('Hand Detection', _enableHand, (v) {
            setState(() => _enableHand = v);
            _emit();
          }),
          if (_enableHand)
            _toggle('Hand Motion Tracking', _handMotion, (v) {
              setState(() => _handMotion = v);
              _emit();
            }),
          if (_enableHand)
            _toggle('Two-Hand Interaction', _twoHandInteraction, (v) {
              setState(() => _twoHandInteraction = v);
              _emit();
            }),
          _toggle('Face Detection', _enableFace, (v) {
            setState(() => _enableFace = v);
            _emit();
          }),
          if (_enableFace)
            _toggle('Emotion Classification', _detectEmotion, (v) {
              setState(() => _detectEmotion = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Face Tracking', _faceTracking, (v) {
              setState(() => _faceTracking = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Face Landmarks (10 points)', _detectLandmarks, (v) {
              setState(() => _detectLandmarks = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Face Contours (disables tracking)', _detectContours, (v) {
              setState(() => _detectContours = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Blink Detection', _blinkDetect, (v) {
              setState(() => _blinkDetect = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Head Nod/Shake Detection', _headGesture, (v) {
              setState(() => _headGesture = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Face Distance Estimation', _faceDistance, (v) {
              setState(() => _faceDistance = v);
              _emit();
            }),
          if (_enableFace)
            _toggle('Attention Scoring', _attentionScore, (v) {
              setState(() => _attentionScore = v);
              _emit();
            }),
          const Divider(height: 32),
          const Text('CAMERA', style: _sectionStyle),
          const SizedBox(height: 8),
          _segmented<CameraFacing>(
            'Camera',
            {CameraFacing.front: 'Front', CameraFacing.back: 'Back'},
            _facing,
            (v) {
              setState(() => _facing = v);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          _segmented<AnalysisResolution>(
            'Resolution',
            {
              AnalysisResolution.low: 'Low',
              AnalysisResolution.medium: 'Medium',
              AnalysisResolution.high: 'High',
            },
            _res,
            (v) {
              setState(() => _res = v);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          // 0 = no throttle (every frame), 5-15 = balanced, 60 = max
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Max Results/sec', style: TextStyle(fontSize: 14)),
                  Text(
                    _maxResults == 0 ? 'No limit' : '$_maxResults/sec',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
              Slider(
                value: _maxResults.toDouble(),
                min: 0,
                max: 30,
                divisions: 6, // 0, 5, 10, 15, 20, 25, 30
                onChanged: (v) {
                  setState(() => _maxResults = v.round());
                  _emit();
                },
              ),
              Text(
                _maxResults == 0
                    ? 'No throttle — smoothest landmark tracking'
                    : _maxResults <= 5
                        ? 'Labels only — choppy landmarks, lightest load'
                        : _maxResults <= 15
                            ? 'Balanced — smooth labels, slight landmark lag'
                            : 'Near-full rate — minimal throttling',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text('HAND CONFIG', style: _sectionStyle),
          const SizedBox(height: 8),
          _segmented<int>(
            'Max Hands',
            {1: '1', 2: '2'},
            _maxHands,
            (v) {
              setState(() => _maxHands = v);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          _slider('Detection Confidence', _minDetConf, 0.1, 1.0, (v) {
            setState(() => _minDetConf = v);
            _emit();
          }),
          _toggle('Gesture Filter (deny fist/palm, high thresholds)', _gestureFilter, (v) {
            setState(() => _gestureFilter = v);
            _emit();
          }),
          const Divider(height: 32),
          const Text('FACE CONFIG', style: _sectionStyle),
          const SizedBox(height: 8),
          _slider('Min Face Size', _minFaceSize, 0.05, 0.5, (v) {
            setState(() => _minFaceSize = v);
            _emit();
          }),
          _toggle('Accurate Mode (slower)', _accurateMode, (v) {
            setState(() => _accurateMode = v);
            _emit();
          }),
          const Divider(height: 32),
          const Text('OVERLAYS', style: _sectionStyle),
          const SizedBox(height: 8),
          _toggle('Hand Landmarks', _showLandmarks, (v) {
            setState(() => _showLandmarks = v);
            _emit();
          }),
          _toggle('Hand Bounding Box', _showHandBox, (v) {
            setState(() => _showHandBox = v);
            _emit();
          }),
          _toggle('Face Bounding Box', _showFaceBox, (v) {
            setState(() => _showFaceBox = v);
            _emit();
          }),
          _toggle('Face Contours Overlay', _showContours, (v) {
            setState(() => _showContours = v);
            _emit();
          }),
          _toggle('Gesture Label', _showGesture, (v) {
            setState(() => _showGesture = v);
            _emit();
          }),
          _toggle('Emotion Label', _showEmotion, (v) {
            setState(() => _showEmotion = v);
            _emit();
          }),
          _toggle('Stats Overlay', _showStats, (v) {
            setState(() => _showStats = v);
            _emit();
          }),
          _toggle('World Coords (pinch/span cm)', _showWorld, (v) {
            setState(() => _showWorld = v);
            _emit();
          }),
          const SizedBox(height: 16),
          Text(
            'Note: Detection and camera changes require Restart to take effect. '
            'Overlay toggles apply instantly.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(value.toStringAsFixed(2),
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 20).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _segmented<T>(
    String label,
    Map<T, String> options,
    T selected,
    ValueChanged<T> onChanged,
  ) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<T>(
                segments: options.entries
                    .map((e) =>
                        ButtonSegment(value: e.key, label: Text(e.value)))
                    .toList(),
                selected: {selected},
                onSelectionChanged: (s) => onChanged(s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _sectionStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.grey,
    letterSpacing: 1.2,
  );
}
