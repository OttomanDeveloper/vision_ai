import 'dart:ui' show Size;

import 'face_result.dart';
import 'hand_result.dart';

class VisionResult {
  final List<HandResult> hands;
  final List<FaceResult> faces;
  final int timestampMs;
  final Size imageSize;
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

  HandResult? get primaryHand => hands.isEmpty
      ? null
      : hands.reduce(
          (a, b) => a.gestureConfidence > b.gestureConfidence ? a : b,
        );

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
