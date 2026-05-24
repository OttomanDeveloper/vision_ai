import 'dart:ui' show Rect;

import 'emotion.dart';

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
  });

  @override
  String toString() =>
      'FaceResult(emotion: $emotion, confidence: $emotionConfidence)';
}
