import 'dart:ui' show Offset, Rect;

import 'emotion.dart';

/// Detection result for a single face with emotion classification.
class FaceResult {
  final Emotion emotion;
  final Map<Emotion, double> emotionScores;
  final double emotionConfidence;
  final Rect boundingBox;
  final double headEulerAngleX;
  final double headEulerAngleY;
  final double headEulerAngleZ;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final int trackingId;

  /// Face contour groups (face outline, eyes, lips, eyebrows, nose).
  /// Each list is a connected sequence of points in image pixel coordinates.
  /// Null when [FaceConfig.detectContours] is false.
  final List<List<Offset>>? contours;

  const FaceResult({
    required this.emotion,
    required this.emotionScores,
    required this.emotionConfidence,
    required this.boundingBox,
    required this.headEulerAngleX,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.trackingId = -1,
    this.contours,
  });

  bool get hasContours => contours != null && contours!.isNotEmpty;

  @override
  String toString() =>
      'FaceResult(emotion: $emotion, confidence: $emotionConfidence)';
}
