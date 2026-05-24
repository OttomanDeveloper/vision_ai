// Standard Flutter plugin platform interface pattern. The token prevents third-party code from
// subclassing VisionAiPlatform without going through the verified setter, which guards against
// accidental or malicious platform swaps at runtime.
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/models/config.dart';
import 'src/models/vision_result.dart';
import 'vision_ai_method_channel.dart';

abstract class VisionAiPlatform extends PlatformInterface {
  VisionAiPlatform() : super(token: _token);

  static final Object _token = Object();

  static VisionAiPlatform _instance = VisionAiMethodChannel();

  static VisionAiPlatform get instance => _instance;

  static set instance(VisionAiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> startCamera({
    required CameraConfig cameraConfig,
    HandConfig? handConfig,
    FaceConfig? faceConfig,
  });

  Future<void> stopCamera();

  Future<void> updateHandConfig(HandConfig config);

  Future<void> updateFaceConfig(FaceConfig config);

  Future<void> switchCamera(CameraFacing facing);

  Future<void> dispose();

  Stream<VisionResult> get resultStream;
}
