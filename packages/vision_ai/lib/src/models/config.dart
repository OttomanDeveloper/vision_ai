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

  /// Whether to detect 10 face landmarks (eye centers, mouth corners, nose,
  /// ears, cheeks). Lighter than contours and works WITH face tracking.
  final bool detectLandmarks;

  /// Whether to detect face contours (face outline, eyes, lips,
  /// eyebrows, nose, cheeks — all 15 ML Kit contour types).
  /// Note: contour mode and face tracking cannot be used together in ML Kit.
  /// When enabled, tracking is automatically disabled.
  final bool detectContours;

  /// Minimum face size as proportion of image width [0.0, 1.0].
  final double minFaceSize;

  /// Assign stable tracking IDs to faces across frames.
  final bool enableTracking;

  /// Minimum confidence to accept an emotion classification [0.0, 1.0].
  final double minEmotionConfidence;

  /// Use ML Kit's accurate detection mode instead of fast mode.
  /// Improves detection quality (fewer missed faces, better landmarks)
  /// at the cost of higher latency (~2-3x slower per frame).
  final bool accurateMode;

  const FaceConfig({
    this.detectEmotion = true,
    this.detectLandmarks = false,
    this.detectContours = false,
    this.minFaceSize = 0.1,
    this.enableTracking = true,
    this.minEmotionConfidence = 0.4,
    this.accurateMode = false,
  });
}

/// Camera configuration.
class CameraConfig {
  final CameraFacing facing;
  final AnalysisResolution resolution;

  /// Maximum detection results delivered to Dart per second.
  ///
  /// Controls how often [VisionAi.results] emits. The ML pipeline still runs
  /// at full speed internally — throttling only skips the emission to Dart,
  /// so the next result that IS emitted is always fresh (not stale).
  ///
  /// **How to choose a value:**
  /// - `0` (default) — No throttle. Every processed frame is emitted.
  ///   Best for smooth hand landmark drawing (~18-30 FPS depending on device).
  /// - `10-15` — Good balance. Gesture/emotion labels update smoothly,
  ///   hand skeleton has slight trailing on fast movement. Saves ~40-50%
  ///   main thread work compared to unthrottled.
  /// - `5` — Labels-only mode. Fine for reading gesture/emotion values,
  ///   but hand skeleton drawing will look choppy. Saves ~70% main thread work.
  ///
  /// Clamped to 1-60 range when set. Values above device processing speed
  /// have no effect (a device processing at 20 FPS won't emit faster than 20).
  final int maxResultsPerSecond;

  const CameraConfig({
    this.facing = CameraFacing.front,
    this.resolution = AnalysisResolution.medium,
    this.maxResultsPerSecond = 0,
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
