import 'finger_state.dart';

enum CameraFacing { front, back }

enum AnalysisResolution { low, medium, high }


class HandConfig {
  final int maxHands;
  final double minDetectionConfidence;
  final double minPresenceConfidence;
  final double minTrackingConfidence;
  final List<CustomGesture> customGestures;

  const HandConfig({
    this.maxHands = 2,
    this.minDetectionConfidence = 0.5,
    this.minPresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.customGestures = const [],
  });
}

class FaceConfig {
  final bool detectEmotion;
  final double minFaceSize;
  final bool enableTracking;
  final double minEmotionConfidence;

  const FaceConfig({
    this.detectEmotion = true,
    this.minFaceSize = 0.1,
    this.enableTracking = true,
    this.minEmotionConfidence = 0.4,
  });
}

class CameraConfig {
  final CameraFacing facing;
  final AnalysisResolution resolution;

  const CameraConfig({
    this.facing = CameraFacing.front,
    this.resolution = AnalysisResolution.medium,
  });
}

class CustomGesture {
  final String name;
  final Map<Finger, FingerState> fingerStates;

  const CustomGesture({
    required this.name,
    required this.fingerStates,
  });
}
