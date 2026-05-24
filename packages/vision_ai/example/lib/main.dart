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

// ---------------------------------------------------------------------------
// Camera lifecycle state
// ---------------------------------------------------------------------------
class _CameraState {
  final int? textureId;
  final bool isStarting;
  final String? permissionError;
  final VisionAi? vision;

  const _CameraState({
    this.textureId,
    this.isStarting = false,
    this.permissionError,
    this.vision,
  });

  bool get isRunning => vision?.isRunning ?? false;

  _CameraState copyWith({
    int? Function()? textureId,
    bool? isStarting,
    String? Function()? permissionError,
    VisionAi? Function()? vision,
  }) {
    return _CameraState(
      textureId: textureId != null ? textureId() : this.textureId,
      isStarting: isStarting ?? this.isStarting,
      permissionError:
          permissionError != null ? permissionError() : this.permissionError,
      vision: vision != null ? vision() : this.vision,
    );
  }
}

// ---------------------------------------------------------------------------
// Detector results (updated from the vision stream)
// ---------------------------------------------------------------------------
class _DetectorState {
  final VisionResult? latestResult;
  final BlinkEvent? lastBlink;
  final HeadGestureEvent? lastHeadGesture;
  final FaceDistanceEstimate? lastDistance;
  final AttentionScore? lastAttention;
  final HandMotion? lastHandMotion;
  final TwoHandEvent? lastTwoHandEvent;

  const _DetectorState({
    this.latestResult,
    this.lastBlink,
    this.lastHeadGesture,
    this.lastDistance,
    this.lastAttention,
    this.lastHandMotion,
    this.lastTwoHandEvent,
  });
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
    this.enableHand = true,
    this.enableFace = true,
    this.detectEmotion = true,
    this.detectLandmarks = false,
    this.detectContours = false,
    this.enableBlinkDetection = false,
    this.enableHeadGesture = false,
    this.enableFaceDistance = false,
    this.enableAttentionScore = false,
    this.enableHandMotion = false,
    this.enableTwoHandInteraction = false,
    this.maxHands = 2,
    this.minDetectionConfidence = 0.5,
    this.enableGestureFilter = false,
    this.minFaceSize = 0.1,
    this.enableFaceTracking = true,
    this.faceAccurateMode = false,
    this.cameraFacing = CameraFacing.front,
    this.resolution = AnalysisResolution.medium,
    this.maxResultsPerSecond = 0,
    this.showHandLandmarks = true,
    this.showHandBoundingBox = false,
    this.showFaceBoundingBox = true,
    this.showFaceContours = false,
    this.showGestureLabel = true,
    this.showEmotionLabel = true,
    this.showStats = true,
    this.showWorldCoords = false,
  });

  _Settings copyWith({
    bool? enableHand,
    bool? enableFace,
    bool? detectEmotion,
    int? maxHands,
    double? minDetectionConfidence,
    bool? enableGestureFilter,
    double? minFaceSize,
    bool? enableFaceTracking,
    bool? faceAccurateMode,
    bool? detectLandmarks,
    bool? detectContours,
    bool? enableBlinkDetection,
    bool? enableHeadGesture,
    bool? enableFaceDistance,
    bool? enableAttentionScore,
    bool? enableHandMotion,
    bool? enableTwoHandInteraction,
    CameraFacing? cameraFacing,
    AnalysisResolution? resolution,
    int? maxResultsPerSecond,
    bool? showHandLandmarks,
    bool? showHandBoundingBox,
    bool? showFaceBoundingBox,
    bool? showFaceContours,
    bool? showGestureLabel,
    bool? showEmotionLabel,
    bool? showStats,
    bool? showWorldCoords,
  }) {
    return _Settings(
      enableHand: enableHand ?? this.enableHand,
      enableFace: enableFace ?? this.enableFace,
      detectEmotion: detectEmotion ?? this.detectEmotion,
      maxHands: maxHands ?? this.maxHands,
      minDetectionConfidence:
          minDetectionConfidence ?? this.minDetectionConfidence,
      enableGestureFilter: enableGestureFilter ?? this.enableGestureFilter,
      minFaceSize: minFaceSize ?? this.minFaceSize,
      enableFaceTracking: enableFaceTracking ?? this.enableFaceTracking,
      faceAccurateMode: faceAccurateMode ?? this.faceAccurateMode,
      detectLandmarks: detectLandmarks ?? this.detectLandmarks,
      detectContours: detectContours ?? this.detectContours,
      enableBlinkDetection: enableBlinkDetection ?? this.enableBlinkDetection,
      enableHeadGesture: enableHeadGesture ?? this.enableHeadGesture,
      enableFaceDistance: enableFaceDistance ?? this.enableFaceDistance,
      enableAttentionScore: enableAttentionScore ?? this.enableAttentionScore,
      enableHandMotion: enableHandMotion ?? this.enableHandMotion,
      enableTwoHandInteraction:
          enableTwoHandInteraction ?? this.enableTwoHandInteraction,
      cameraFacing: cameraFacing ?? this.cameraFacing,
      resolution: resolution ?? this.resolution,
      maxResultsPerSecond: maxResultsPerSecond ?? this.maxResultsPerSecond,
      showHandLandmarks: showHandLandmarks ?? this.showHandLandmarks,
      showHandBoundingBox: showHandBoundingBox ?? this.showHandBoundingBox,
      showFaceBoundingBox: showFaceBoundingBox ?? this.showFaceBoundingBox,
      showFaceContours: showFaceContours ?? this.showFaceContours,
      showGestureLabel: showGestureLabel ?? this.showGestureLabel,
      showEmotionLabel: showEmotionLabel ?? this.showEmotionLabel,
      showStats: showStats ?? this.showStats,
      showWorldCoords: showWorldCoords ?? this.showWorldCoords,
    );
  }
}

// ---------------------------------------------------------------------------
// CameraPage
// ---------------------------------------------------------------------------
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _camera = ValueNotifier<_CameraState>(const _CameraState());
  final _settings = ValueNotifier<_Settings>(const _Settings());
  final _detectors = ValueNotifier<_DetectorState>(const _DetectorState());

  StreamSubscription<VisionResult>? _resultSub;
  BlinkDetector? _blinkDetector;
  HeadGestureDetector? _headGestureDetector;
  FaceDistanceEstimator? _distanceEstimator;
  AttentionScorer? _attentionScorer;
  HandMotionTracker? _handMotionTracker;
  TwoHandInteractionDetector? _twoHandDetector;

  VisionAi _createVision() {
    final s = _settings.value;
    return VisionAi(
      hand: s.enableHand
          ? HandConfig(
              maxHands: s.maxHands,
              minDetectionConfidence: s.minDetectionConfidence,
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
              deniedGestures: s.enableGestureFilter
                  ? {Gesture.fist, Gesture.openHand}
                  : null,
              gestureThresholds: s.enableGestureFilter
                  ? {Gesture.thumbsUp: 0.8, Gesture.peace: 0.7}
                  : null,
            )
          : null,
      face: s.enableFace
          ? FaceConfig(
              detectEmotion: s.detectEmotion,
              detectLandmarks: s.detectLandmarks,
              detectContours: s.detectContours,
              minFaceSize: s.minFaceSize,
              enableTracking: s.enableFaceTracking,
              accurateMode: s.faceAccurateMode,
            )
          : null,
      camera: CameraConfig(
        facing: s.cameraFacing,
        resolution: s.resolution,
        maxResultsPerSecond: s.maxResultsPerSecond,
      ),
    );
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    if (result.isGranted) return true;
    _camera.value = _camera.value.copyWith(
      permissionError: () => result.isPermanentlyDenied
          ? 'Camera permission permanently denied. Enable in Settings.'
          : 'Camera permission is required.',
    );
    return false;
  }

  Future<void> _start() async {
    final cam = _camera.value;
    if (cam.isStarting || cam.isRunning) return;
    final s = _settings.value;
    if (!s.enableHand && !s.enableFace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable at least hand or face detection')),
      );
      return;
    }

    _camera.value = _camera.value.copyWith(
      isStarting: true,
      permissionError: () => null,
    );

    if (!await _requestCameraPermission()) {
      _camera.value = _camera.value.copyWith(isStarting: false);
      return;
    }

    try {
      cam.vision?.dispose();
      final vision = _createVision();
      final textureId = await vision.start();

      if (s.enableBlinkDetection) _blinkDetector = BlinkDetector();
      if (s.enableHeadGesture) _headGestureDetector = HeadGestureDetector();
      if (s.enableFaceDistance) _distanceEstimator = FaceDistanceEstimator();
      if (s.enableAttentionScore) _attentionScorer = AttentionScorer();
      if (s.enableHandMotion) _handMotionTracker = HandMotionTracker();
      if (s.enableTwoHandInteraction) {
        _twoHandDetector = TwoHandInteractionDetector();
      }

      _resultSub = vision.results.listen((r) {
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
        final prev = _detectors.value;
        _detectors.value = _DetectorState(
          latestResult: r,
          lastBlink: blink ?? prev.lastBlink,
          lastHeadGesture: headGesture ?? prev.lastHeadGesture,
          lastDistance: dist ?? prev.lastDistance,
          lastAttention: attention ?? prev.lastAttention,
          lastHandMotion: handMotion ?? prev.lastHandMotion,
          lastTwoHandEvent: twoHandEvent ?? prev.lastTwoHandEvent,
        );
      });

      _camera.value = _CameraState(
        textureId: textureId,
        isStarting: false,
        vision: vision,
      );
    } catch (e) {
      _camera.value = _camera.value.copyWith(isStarting: false);
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
    await _camera.value.vision?.stop();
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
    _camera.value = const _CameraState();
    _detectors.value = const _DetectorState();
  }

  Future<void> _restart() async {
    await _stop();
    await _start();
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    _camera.value.vision?.dispose();
    _camera.dispose();
    _settings.dispose();
    _detectors.dispose();
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
      builder: (_) => _SettingsSheet(settings: _settings),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            child: ValueListenableBuilder<_CameraState>(
              valueListenable: _camera,
              builder: (context, cam, _) {
                if (cam.textureId == null) {
                  return ValueListenableBuilder<_Settings>(
                    valueListenable: _settings,
                    builder: (context, s, _) => _IdleView(
                      enableHand: s.enableHand,
                      enableFace: s.enableFace,
                      permissionError: cam.permissionError,
                    ),
                  );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ValueListenableBuilder<_Settings>(
                      valueListenable: _settings,
                      builder: (context, s, _) => VisionAiCameraView(
                        controller: cam.vision!,
                        textureId: cam.textureId!,
                        showHandLandmarks: s.showHandLandmarks,
                        showHandBoundingBox: s.showHandBoundingBox,
                        showFaceBoundingBox: s.showFaceBoundingBox,
                        showFaceContours: s.showFaceContours,
                        showGestureLabel: s.showGestureLabel,
                        showEmotionLabel: s.showEmotionLabel,
                      ),
                    ),
                    ValueListenableBuilder<_Settings>(
                      valueListenable: _settings,
                      builder: (context, s, _) {
                        if (!s.showStats) return const SizedBox.shrink();
                        return ValueListenableBuilder<_DetectorState>(
                          valueListenable: _detectors,
                          builder: (context, det, _) {
                            if (det.latestResult == null) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              bottom: 8,
                              right: 8,
                              child: _StatsOverlay(
                                result: det.latestResult!,
                                lastBlink: det.lastBlink,
                                lastHeadGesture: det.lastHeadGesture,
                                lastDistance: det.lastDistance,
                                lastAttention: det.lastAttention,
                                lastHandMotion: det.lastHandMotion,
                                lastTwoHandEvent: det.lastTwoHandEvent,
                                showWorldCoords: s.showWorldCoords,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ValueListenableBuilder<_CameraState>(
                valueListenable: _camera,
                builder: (context, cam, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          (cam.isRunning || cam.isStarting) ? null : _start,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(cam.isStarting ? 'Starting...' : 'Start'),
                    ),
                    ElevatedButton.icon(
                      onPressed: cam.isRunning ? _stop : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                    if (cam.isRunning)
                      ElevatedButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Restart'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle view (camera not started)
// ---------------------------------------------------------------------------
class _IdleView extends StatelessWidget {
  final bool enableHand;
  final bool enableFace;
  final String? permissionError;

  const _IdleView({
    required this.enableHand,
    required this.enableFace,
    this.permissionError,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text('Tap Start to begin', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            '${enableHand ? "Hand" : ""}${enableHand && enableFace ? " + " : ""}${enableFace ? "Face" : ""} detection',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          if (permissionError != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                permissionError!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 14),
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

  const _StatsOverlay({
    required this.result,
    this.lastBlink,
    this.lastHeadGesture,
    this.lastDistance,
    this.lastAttention,
    this.lastHandMotion,
    this.lastTwoHandEvent,
    this.showWorldCoords = false,
  });

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
            _line('Confidence',
                '${(hand.gestureConfidence * 100).toStringAsFixed(0)}%'),
            _line('Side', hand.isLeftHand ? 'Left' : 'Right'),
            _line(
              'Fingers',
              [
                hand.fingerStates[Finger.thumb] == FingerState.extended
                    ? 'T'
                    : '',
                hand.fingerStates[Finger.indexFinger] == FingerState.extended
                    ? 'I'
                    : '',
                hand.fingerStates[Finger.middle] == FingerState.extended
                    ? 'M'
                    : '',
                hand.fingerStates[Finger.ring] == FingerState.extended
                    ? 'R'
                    : '',
                hand.fingerStates[Finger.pinky] == FingerState.extended
                    ? 'P'
                    : '',
              ].where((s) => s.isNotEmpty).join(''),
            ),
            if (showWorldCoords && hand.worldLandmarks.length >= 21) ...[
              _line(
                  'Pinch',
                  '${(hand.worldLandmarks[HandLandmarkIndex.thumbTip].distanceTo(hand.worldLandmarks[HandLandmarkIndex.indexTip]) * 100).toStringAsFixed(1)}cm'),
              _line(
                  'Span',
                  '${(hand.worldLandmarks[HandLandmarkIndex.thumbTip].distanceTo(hand.worldLandmarks[HandLandmarkIndex.pinkyTip]) * 100).toStringAsFixed(1)}cm'),
            ],
            if (lastHandMotion != null)
              _line('Motion',
                  '${lastHandMotion!.state.name} ${lastHandMotion!.direction.name} (${lastHandMotion!.speed.toStringAsFixed(2)}/s)'),
          ],
          if (lastTwoHandEvent != null)
            _line('2-Hand',
                '${lastTwoHandEvent!.gesture.name} (d=${lastTwoHandEvent!.distance.toStringAsFixed(3)})'),
          if (face != null && face.emotion.isRecognized) ...[
            _line('Emotion', face.emotion.name),
            _line('Emotion %',
                '${(face.emotionConfidence * 100).toStringAsFixed(0)}%'),
            if (face.smilingProbability != null)
              _line('Smile',
                  '${(face.smilingProbability! * 100).toStringAsFixed(0)}%'),
          ],
          if (lastBlink != null)
            _line(
                'Blink', '${lastBlink!.eye.name} (${lastBlink!.durationMs}ms)'),
          if (lastHeadGesture != null)
            _line(
                'Head',
                lastHeadGesture!.gesture == HeadGesture.nod
                    ? 'YES (nod)'
                    : 'NO (shake)'),
          if (lastDistance != null)
            _line('Distance',
                '${lastDistance!.distanceCm.toStringAsFixed(0)}cm (${lastDistance!.zone.name})'),
          if (lastAttention != null) ...[
            _line('Attention',
                '${(lastAttention!.score * 100).toStringAsFixed(0)}% (${lastAttention!.level.name})'),
            _line('  Eye',
                '${(lastAttention!.eyeScore * 100).toStringAsFixed(0)}%'),
            _line('  Orient',
                '${(lastAttention!.orientationScore * 100).toStringAsFixed(0)}%'),
            _line('  Stable',
                '${(lastAttention!.stabilityScore * 100).toStringAsFixed(0)}%'),
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
// Settings bottom sheet
// ---------------------------------------------------------------------------
class _SettingsSheet extends StatelessWidget {
  final ValueNotifier<_Settings> settings;

  const _SettingsSheet({required this.settings});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => ValueListenableBuilder<_Settings>(
        valueListenable: settings,
        builder: (context, s, _) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('DETECTION', style: _sectionStyle),
            const SizedBox(height: 8),
            _toggle('Hand Detection', s.enableHand,
                (v) => settings.value = s.copyWith(enableHand: v)),
            if (s.enableHand)
              _toggle('Hand Motion Tracking', s.enableHandMotion,
                  (v) => settings.value = s.copyWith(enableHandMotion: v)),
            if (s.enableHand)
              _toggle(
                  'Two-Hand Interaction',
                  s.enableTwoHandInteraction,
                  (v) => settings.value =
                      s.copyWith(enableTwoHandInteraction: v)),
            _toggle('Face Detection', s.enableFace,
                (v) => settings.value = s.copyWith(enableFace: v)),
            if (s.enableFace)
              _toggle('Emotion Classification', s.detectEmotion,
                  (v) => settings.value = s.copyWith(detectEmotion: v)),
            if (s.enableFace)
              _toggle('Face Tracking', s.enableFaceTracking,
                  (v) => settings.value = s.copyWith(enableFaceTracking: v)),
            if (s.enableFace)
              _toggle('Face Landmarks (10 points)', s.detectLandmarks,
                  (v) => settings.value = s.copyWith(detectLandmarks: v)),
            if (s.enableFace)
              _toggle(
                  'Face Contours (disables tracking)',
                  s.detectContours,
                  (v) => settings.value = s.copyWith(detectContours: v)),
            if (s.enableFace)
              _toggle('Blink Detection', s.enableBlinkDetection,
                  (v) => settings.value = s.copyWith(enableBlinkDetection: v)),
            if (s.enableFace)
              _toggle('Head Nod/Shake Detection', s.enableHeadGesture,
                  (v) => settings.value = s.copyWith(enableHeadGesture: v)),
            if (s.enableFace)
              _toggle('Face Distance Estimation', s.enableFaceDistance,
                  (v) => settings.value = s.copyWith(enableFaceDistance: v)),
            if (s.enableFace)
              _toggle('Attention Scoring', s.enableAttentionScore,
                  (v) => settings.value = s.copyWith(enableAttentionScore: v)),
            const Divider(height: 32),
            const Text('CAMERA', style: _sectionStyle),
            const SizedBox(height: 8),
            _segmented<CameraFacing>(
              'Camera',
              {CameraFacing.front: 'Front', CameraFacing.back: 'Back'},
              s.cameraFacing,
              (v) => settings.value = s.copyWith(cameraFacing: v),
            ),
            const SizedBox(height: 12),
            _segmented<AnalysisResolution>(
              'Resolution',
              {
                AnalysisResolution.low: 'Low',
                AnalysisResolution.medium: 'Medium',
                AnalysisResolution.high: 'High',
              },
              s.resolution,
              (v) => settings.value = s.copyWith(resolution: v),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Max Results/sec',
                        style: TextStyle(fontSize: 14)),
                    Text(
                      s.maxResultsPerSecond == 0
                          ? 'No limit'
                          : '${s.maxResultsPerSecond}/sec',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
                Slider(
                  value: s.maxResultsPerSecond.toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 6,
                  onChanged: (v) => settings.value =
                      s.copyWith(maxResultsPerSecond: v.round()),
                ),
                Text(
                  s.maxResultsPerSecond == 0
                      ? 'No throttle — smoothest landmark tracking'
                      : s.maxResultsPerSecond <= 5
                          ? 'Labels only — choppy landmarks, lightest load'
                          : s.maxResultsPerSecond <= 15
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
              s.maxHands,
              (v) => settings.value = s.copyWith(maxHands: v),
            ),
            const SizedBox(height: 12),
            _slider('Detection Confidence', s.minDetectionConfidence, 0.1, 1.0,
                (v) => settings.value = s.copyWith(minDetectionConfidence: v)),
            _toggle(
                'Gesture Filter (deny fist/palm, high thresholds)',
                s.enableGestureFilter,
                (v) => settings.value = s.copyWith(enableGestureFilter: v)),
            const Divider(height: 32),
            const Text('FACE CONFIG', style: _sectionStyle),
            const SizedBox(height: 8),
            _slider('Min Face Size', s.minFaceSize, 0.05, 0.5,
                (v) => settings.value = s.copyWith(minFaceSize: v)),
            _toggle('Accurate Mode (slower)', s.faceAccurateMode,
                (v) => settings.value = s.copyWith(faceAccurateMode: v)),
            const Divider(height: 32),
            const Text('OVERLAYS', style: _sectionStyle),
            const SizedBox(height: 8),
            _toggle('Hand Landmarks', s.showHandLandmarks,
                (v) => settings.value = s.copyWith(showHandLandmarks: v)),
            _toggle('Hand Bounding Box', s.showHandBoundingBox,
                (v) => settings.value = s.copyWith(showHandBoundingBox: v)),
            _toggle('Face Bounding Box', s.showFaceBoundingBox,
                (v) => settings.value = s.copyWith(showFaceBoundingBox: v)),
            _toggle('Face Contours Overlay', s.showFaceContours,
                (v) => settings.value = s.copyWith(showFaceContours: v)),
            _toggle('Gesture Label', s.showGestureLabel,
                (v) => settings.value = s.copyWith(showGestureLabel: v)),
            _toggle('Emotion Label', s.showEmotionLabel,
                (v) => settings.value = s.copyWith(showEmotionLabel: v)),
            _toggle('Stats Overlay', s.showStats,
                (v) => settings.value = s.copyWith(showStats: v)),
            _toggle('World Coords (pinch/span cm)', s.showWorldCoords,
                (v) => settings.value = s.copyWith(showWorldCoords: v)),
            const SizedBox(height: 16),
            Text(
              'Note: Detection and camera changes require Restart to take effect. '
              'Overlay toggles apply instantly.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static Widget _toggle(
          String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: EdgeInsets.zero,
      );

  static Widget _slider(String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      Column(
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

  static Widget _segmented<T>(String label, Map<T, String> options, T selected,
          ValueChanged<T> onChanged) =>
      Row(
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

  static const _sectionStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.grey,
    letterSpacing: 1.2,
  );
}
