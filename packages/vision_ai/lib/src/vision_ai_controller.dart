import 'dart:async';

import 'models/config.dart';
import 'models/vision_result.dart';
import '../vision_ai_platform_interface.dart';

/// On-device hand gesture recognition and facial emotion detection.
///
/// Processes a live camera feed at 20-30 FPS using MediaPipe (hand gestures)
/// and ML Kit + TFLite (face emotions). All inference runs on-device with
/// zero cloud dependencies.
///
/// ```dart
/// final vision = VisionAi(
///   hand: HandConfig(maxHands: 2),
///   face: FaceConfig(detectEmotion: true),
/// );
/// final textureId = await vision.start();
/// vision.results.listen((result) {
///   print(result.primaryHand?.gesture);
///   print(result.primaryFace?.emotion);
/// });
/// ```
class VisionAi {
  final HandConfig? _handConfig;
  final FaceConfig? _faceConfig;
  final CameraConfig _cameraConfig;

  // Guards against calling start/results after dispose.
  bool _isRunning = false;
  bool _isDisposed = false;

  /// Creates a detector with hand gestures, face emotions, or both.
  ///
  /// At least one of [hand] or [face] must be provided.
  VisionAi({
    HandConfig? hand,
    FaceConfig? face,
    CameraConfig camera = const CameraConfig(),
  })  : assert(hand != null || face != null,
            'Provide at least one of hand or face config'),
        _handConfig = hand,
        _faceConfig = face,
        _cameraConfig = camera;

  /// Hand gesture detection only.
  factory VisionAi.hand({
    HandConfig config = const HandConfig(),
    CameraConfig camera = const CameraConfig(),
  }) =>
      VisionAi(hand: config, camera: camera);

  /// Face emotion detection only.
  factory VisionAi.face({
    FaceConfig config = const FaceConfig(),
    CameraConfig camera = const CameraConfig(),
  }) =>
      VisionAi(face: config, camera: camera);

  // Indirection lets tests swap the platform without touching this class.
  VisionAiPlatform get _platform => VisionAiPlatform.instance;

  /// Whether the detector is currently processing camera frames.
  bool get isRunning => _isRunning;

  /// Stream of detection results, emitted for each processed frame.
  Stream<VisionResult> get results {
    _ensureNotDisposed();
    return _platform.resultStream;
  }

  /// Starts the camera and begins processing frames.
  ///
  /// Returns a texture ID for rendering the camera preview via [Texture] widget.
  /// Throws [PlatformException] if camera access fails.
  Future<int> start() async {
    _ensureNotDisposed();
    // Guard prevents double-starting; -1 signals "already running" to callers.
    if (_isRunning) return -1;

    final textureId = await _platform.startCamera(
      cameraConfig: _cameraConfig,
      handConfig: _handConfig,
      faceConfig: _faceConfig,
    );

    _isRunning = true;
    return textureId;
  }

  /// Stops processing and releases the camera. Safe to call when not running.
  Future<void> stop() async {
    if (!_isRunning) return;
    await _platform.stopCamera();
    _isRunning = false;
  }

  /// Updates hand detection config while running.
  Future<void> updateHandConfig(HandConfig config) {
    _ensureNotDisposed();
    return _platform.updateHandConfig(config);
  }

  /// Updates face detection config while running.
  Future<void> updateFaceConfig(FaceConfig config) {
    _ensureNotDisposed();
    return _platform.updateFaceConfig(config);
  }

  /// Switches between front and back camera while running.
  Future<void> switchCamera(CameraFacing facing) {
    _ensureNotDisposed();
    return _platform.switchCamera(facing);
  }

  /// Releases all resources. The instance cannot be reused after disposal.
  Future<void> dispose() async {
    if (_isDisposed) return;
    // Mark disposed before awaiting native to block re-entrant calls.
    _isDisposed = true;
    _isRunning = false;
    await _platform.dispose();
  }

  // Throws StateError rather than silently failing so callers catch lifecycle bugs early.
  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError(
        'VisionAi has been disposed. Create a new instance.',
      );
    }
  }
}
