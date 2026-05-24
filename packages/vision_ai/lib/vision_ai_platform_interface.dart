// Standard Flutter plugin platform interface pattern. The token prevents third-party code from
// subclassing VisionAiPlatform without going through the verified setter, which guards against
// accidental or malicious platform swaps at runtime.
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/models/config.dart';
import 'src/models/vision_result.dart';
import 'vision_ai_method_channel.dart';

abstract class VisionAiPlatform extends PlatformInterface {
  VisionAiPlatform() : super(token: _token);

  // Unique sentinel — only subclasses constructed via this library pass verifyToken.
  static final Object _token = Object();

  // Defaults to MethodChannel; tests swap this to a mock implementation.
  static VisionAiPlatform _instance = VisionAiMethodChannel();

  static VisionAiPlatform get instance => _instance;

  // verifyToken throws if [instance] wasn't constructed with _token, preventing rogue swaps.
  static set instance(VisionAiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Returns the native texture ID for rendering camera preview via the Texture widget.
  Future<int> startCamera({
    required CameraConfig cameraConfig,
    HandConfig? handConfig,
    FaceConfig? faceConfig,
  });

  Future<void> stopCamera();

  // Hot-updates confidence thresholds and gesture filters without restarting the pipeline.
  Future<void> updateHandConfig(HandConfig config);

  // Hot-updates emotion and contour options without restarting the pipeline.
  Future<void> updateFaceConfig(FaceConfig config);

  Future<void> switchCamera(CameraFacing facing);

  // Releases the native camera and ML resources. Do not call platform methods after this.
  Future<void> dispose();

  // Broadcast stream; multiple listeners safe — all share a single platform subscription.
  Stream<VisionResult> get resultStream;
}
