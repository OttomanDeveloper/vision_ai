import 'finger_state.dart';

enum CameraFacing { front, back }

/// Camera analysis resolution. Lower is faster, higher is more accurate.
enum AnalysisResolution { low, medium, high }

/// Configuration for hand gesture detection.
class HandConfig {
  /// Maximum hands to detect (1 or 2).
  final int maxHands;

  /// Minimum confidence for initial hand detection [0.0, 1.0].
  final double minDetectionConfidence;

  /// Minimum confidence for hand presence between frames [0.0, 1.0].
  final double minPresenceConfidence;

  /// Minimum confidence for landmark tracking [0.0, 1.0].
  final double minTrackingConfidence;

  /// Custom gestures to recognize beyond the 13 built-in ones.
  final List<CustomGesture> customGestures;

  const HandConfig({
    this.maxHands = 2,
    this.minDetectionConfidence = 0.5,
    this.minPresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.customGestures = const [],
  });
}

/// Configuration for face emotion detection.
class FaceConfig {
  /// Whether to run the TFLite emotion classifier (adds ~5-15ms latency).
  final bool detectEmotion;

  /// Minimum face size as proportion of image width [0.0, 1.0].
  final double minFaceSize;

  /// Assign stable tracking IDs to faces across frames.
  final bool enableTracking;

  /// Minimum confidence to accept an emotion classification [0.0, 1.0].
  final double minEmotionConfidence;

  const FaceConfig({
    this.detectEmotion = true,
    this.minFaceSize = 0.1,
    this.enableTracking = true,
    this.minEmotionConfidence = 0.4,
  });
}

/// Camera configuration.
class CameraConfig {
  final CameraFacing facing;
  final AnalysisResolution resolution;

  const CameraConfig({
    this.facing = CameraFacing.front,
    this.resolution = AnalysisResolution.medium,
  });
}

/// A user-defined gesture pattern based on finger states.
///
/// Fingers not included in [fingerStates] are treated as "any state" (wildcard).
///
/// ```dart
/// CustomGesture(
///   name: 'rock',
///   fingerStates: {
///     Finger.indexFinger: FingerState.extended,
///     Finger.pinky: FingerState.extended,
///     Finger.thumb: FingerState.closed,
///     Finger.middle: FingerState.closed,
///     Finger.ring: FingerState.closed,
///   },
/// )
/// ```
class CustomGesture {
  final String name;
  final Map<Finger, FingerState> fingerStates;

  const CustomGesture({
    required this.name,
    required this.fingerStates,
  });
}
