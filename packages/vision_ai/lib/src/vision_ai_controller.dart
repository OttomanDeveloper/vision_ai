import 'dart:async';

import 'models/config.dart';
import 'models/vision_result.dart';
import '../vision_ai_platform_interface.dart';

class VisionAi {
  final HandConfig? _handConfig;
  final FaceConfig? _faceConfig;
  final CameraConfig _cameraConfig;

  bool _isRunning = false;
  bool _isDisposed = false;

  VisionAi({
    HandConfig? hand,
    FaceConfig? face,
    CameraConfig camera = const CameraConfig(),
  })  : assert(hand != null || face != null,
            'Provide at least one of hand or face config'),
        _handConfig = hand,
        _faceConfig = face,
        _cameraConfig = camera;

  factory VisionAi.hand({
    HandConfig config = const HandConfig(),
    CameraConfig camera = const CameraConfig(),
  }) =>
      VisionAi(hand: config, camera: camera);

  factory VisionAi.face({
    FaceConfig config = const FaceConfig(),
    CameraConfig camera = const CameraConfig(),
  }) =>
      VisionAi(face: config, camera: camera);

  VisionAiPlatform get _platform => VisionAiPlatform.instance;

  bool get isRunning => _isRunning;

  Stream<VisionResult> get results {
    _ensureNotDisposed();
    return _platform.resultStream;
  }

  Future<int> start() async {
    _ensureNotDisposed();
    if (_isRunning) return -1;

    final textureId = await _platform.startCamera(
      cameraConfig: _cameraConfig,
      handConfig: _handConfig,
      faceConfig: _faceConfig,
    );

    _isRunning = true;
    return textureId;
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _platform.stopCamera();
    _isRunning = false;
  }

  Future<void> updateHandConfig(HandConfig config) {
    _ensureNotDisposed();
    return _platform.updateHandConfig(config);
  }

  Future<void> updateFaceConfig(FaceConfig config) {
    _ensureNotDisposed();
    return _platform.updateFaceConfig(config);
  }

  Future<void> switchCamera(CameraFacing facing) {
    _ensureNotDisposed();
    return _platform.switchCamera(facing);
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isRunning = false;
    await _platform.dispose();
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError(
        'VisionAi has been disposed. Create a new instance.',
      );
    }
  }
}
