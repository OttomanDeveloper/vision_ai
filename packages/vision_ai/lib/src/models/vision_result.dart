import 'dart:ui' show Size;

import 'face_result.dart';
import 'hand_result.dart';

/// Combined detection results from a single camera frame.
class VisionResult {
  // Empty list (not null) when no hands were detected in the frame.
  final List<HandResult> hands;
  // Empty list (not null) when no faces were detected in the frame.
  final List<FaceResult> faces;
  // Milliseconds since epoch at the moment native captured the frame.
  final int timestampMs;
  // Pixel dimensions of the analysis image; may differ from preview widget size.
  final Size imageSize;
  // ML inference duration only; excludes camera capture and serialization overhead.
  final int inferenceTimeMs;

  const VisionResult({
    required this.hands,
    required this.faces,
    required this.timestampMs,
    required this.imageSize,
    required this.inferenceTimeMs,
  });

  bool get hasHands => hands.isNotEmpty;
  bool get hasFaces => faces.isNotEmpty;

  // Returns the hand with the highest gesture confidence, not necessarily the first detected.
  HandResult? get primaryHand => hands.isEmpty
      ? null
      : hands.reduce(
          (a, b) => a.gestureConfidence > b.gestureConfidence ? a : b,
        );

  // Returns the face with the highest emotion confidence, not necessarily the largest face.
  FaceResult? get primaryFace => faces.isEmpty
      ? null
      : faces.reduce(
          (a, b) => a.emotionConfidence > b.emotionConfidence ? a : b,
        );

  @override
  String toString() =>
      'VisionResult(hands: ${hands.length}, faces: ${faces.length}, '
      'inference: ${inferenceTimeMs}ms)';
}
