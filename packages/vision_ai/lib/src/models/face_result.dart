import 'dart:ui' show Offset, Rect;

import 'emotion.dart';

/// Detection result for a single face with emotion classification.
class FaceResult {
  // Dominant emotion; Emotion.none if classifier was skipped or below threshold.
  final Emotion emotion;
  // All seven FER2013 emotion scores in [0.0, 1.0]; sum is approximately 1.0.
  final Map<Emotion, double> emotionScores;
  // Confidence of the dominant emotion; mirrors emotionScores[emotion].
  final double emotionConfidence;
  // In image pixel coordinates, not normalized; size matches the analysis resolution.
  final Rect boundingBox;
  // Pitch in degrees; positive = face tilted up.
  final double headEulerAngleX;
  // Yaw in degrees; positive = face turned right (from camera's perspective).
  final double headEulerAngleY;
  // Roll in degrees; positive = face tilted right (clockwise).
  final double headEulerAngleZ;
  // Probability in [0.0, 1.0]; null when ML Kit's classification model is inactive.
  final double? smilingProbability;
  // Probability in [0.0, 1.0]; null when ML Kit's classification model is inactive.
  final double? leftEyeOpenProbability;
  // Probability in [0.0, 1.0]; null when ML Kit's classification model is inactive.
  final double? rightEyeOpenProbability;
  // -1 when tracking is disabled or this is the face's first appearance in a frame.
  final int trackingId;

  /// 10 face landmark positions in image pixel coordinates.
  /// Order: leftEye, rightEye, noseBase, mouthLeft, mouthRight, mouthBottom,
  /// leftEar, rightEar, leftCheek, rightCheek.
  /// Points with x=-1,y=-1 are not visible (face turned away).
  /// Null when [FaceConfig.detectLandmarks] is false.
  final List<Offset>? landmarks;

  /// Face contour groups (face outline, eyes, lips, eyebrows, nose, cheeks).
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
    this.landmarks,
    this.contours,
  });

  // Returns false for null or empty contours to simplify painter guard logic.
  bool get hasContours => contours != null && contours!.isNotEmpty;

  @override
  String toString() =>
      'FaceResult(emotion: $emotion, confidence: $emotionConfidence)';
}
