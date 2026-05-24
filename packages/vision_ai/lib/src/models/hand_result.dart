import 'dart:ui' show Rect;

import 'finger_state.dart';
import 'gesture.dart';
import 'landmark.dart';

/// Detection result for a single hand.
class HandResult {
  final Gesture gesture;
  final String? customGestureName;
  final double gestureConfidence;

  /// 21 hand landmarks in normalized image coordinates [0.0, 1.0].
  /// Use for rendering overlays on the camera preview.
  final List<NormalizedLandmark> landmarks;

  /// 21 hand landmarks in real-world coordinates (meters).
  /// Origin is the hand's geometric center. Use for measuring physical
  /// distances (hand span, pinch gap, distance between two hands).
  final List<WorldLandmark> worldLandmarks;
  final bool isLeftHand;
  final double handednessConfidence;
  final Map<Finger, FingerState> fingerStates;

  const HandResult({
    required this.gesture,
    this.customGestureName,
    required this.gestureConfidence,
    required this.landmarks,
    required this.worldLandmarks,
    required this.isLeftHand,
    required this.handednessConfidence,
    required this.fingerStates,
  });

  /// Bounding box in normalized [0.0, 1.0] coordinates, computed from the
  /// min/max of all 21 landmarks. Returns null if landmarks are empty.
  Rect? get boundingBox {
    if (landmarks.isEmpty) return null;
    var minX = landmarks[0].x;
    var minY = landmarks[0].y;
    var maxX = landmarks[0].x;
    var maxY = landmarks[0].y;
    for (var i = 1; i < landmarks.length; i++) {
      final lm = landmarks[i];
      if (lm.x < minX) minX = lm.x;
      if (lm.y < minY) minY = lm.y;
      if (lm.x > maxX) maxX = lm.x;
      if (lm.y > maxY) maxY = lm.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  String toString() =>
      'HandResult(gesture: $gesture, confidence: $gestureConfidence, '
      'isLeft: $isLeftHand)';
}
