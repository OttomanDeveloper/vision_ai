import 'finger_state.dart';
import 'gesture.dart';
import 'landmark.dart';

/// Detection result for a single hand.
class HandResult {
  final Gesture gesture;
  final String? customGestureName;
  final double gestureConfidence;
  final List<NormalizedLandmark> landmarks;
  final List<NormalizedLandmark> worldLandmarks;
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

  @override
  String toString() =>
      'HandResult(gesture: $gesture, confidence: $gestureConfidence, '
      'isLeft: $isLeftHand)';
}
