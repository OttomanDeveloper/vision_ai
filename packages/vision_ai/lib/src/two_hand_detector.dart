import 'dart:math' as math;

import 'models/hand_result.dart';
import 'models/landmark.dart';
import 'models/vision_result.dart';

/// Type of two-hand interaction detected.
enum TwoHandGesture {
  /// Index fingertips of both hands are close together.
  pinch,

  /// Palms approaching each other rapidly and making contact.
  clap,

  /// Any fingertips from opposite hands are within touch threshold.
  touching,
}

/// Emitted when a two-hand interaction is detected.
class TwoHandEvent {
  final TwoHandGesture gesture;

  /// Distance between the key contact points in normalized image units.
  /// For pinch: distance between index tips.
  /// For clap/touching: closest fingertip pair distance.
  final double distance;

  /// Timestamp when the interaction was detected.
  final int timestampMs;

  const TwoHandEvent({
    required this.gesture,
    required this.distance,
    required this.timestampMs,
  });

  @override
  String toString() => 'TwoHandEvent(${gesture.name}, d=${distance.toStringAsFixed(3)})';
}

/// Detects interactions between two hands: pinch, clap, and touching.
///
/// Requires two hands in the [VisionResult]. Uses normalized landmarks
/// (shared image coordinate space) to measure cross-hand distances.
///
/// **Pinch**: both index fingertips within [pinchThreshold].
///
/// **Clap**: palms (wrists) approaching rapidly (velocity > [clapVelocityThreshold])
/// and fingertips within [touchThreshold]. Fires once per approach.
///
/// **Touching**: any fingertip from one hand is within [touchThreshold] of
/// any fingertip on the other hand, when it's not a pinch or clap.
///
/// Usage:
/// ```dart
/// final detector = TwoHandInteractionDetector();
///
/// vision.results.listen((result) {
///   final event = detector.update(result);
///   if (event != null) {
///     print('${event.gesture.name} at distance ${event.distance}');
///   }
/// });
///
/// detector.reset();
/// ```
class TwoHandInteractionDetector {
  /// Max normalized distance between index tips to count as a pinch.
  final double pinchThreshold;

  /// Max normalized distance between any two fingertips to count as touching.
  final double touchThreshold;

  /// Minimum wrist approach speed (normalized units/sec) to trigger a clap.
  final double clapVelocityThreshold;

  /// Cooldown (ms) after a detection before another can fire.
  final int cooldownMs;

  TwoHandInteractionDetector({
    this.pinchThreshold = 0.06,
    this.touchThreshold = 0.08,
    this.clapVelocityThreshold = 0.3,
    this.cooldownMs = 500,
  });

  double? _prevWristDistance;
  int? _prevTimestampMs;
  int _lastDetectionMs = 0;

  static const _fingertipIndices = [
    HandLandmarkIndex.thumbTip,
    HandLandmarkIndex.indexTip,
    HandLandmarkIndex.middleTip,
    HandLandmarkIndex.ringTip,
    HandLandmarkIndex.pinkyTip,
  ];

  /// Feed a vision result and get back a [TwoHandEvent] if an interaction
  /// was detected. Returns null if fewer than 2 hands, or no interaction.
  TwoHandEvent? update(VisionResult result) {
    if (result.hands.length < 2) {
      _prevWristDistance = null;
      _prevTimestampMs = null;
      return null;
    }

    final ts = result.timestampMs;

    // Cooldown
    if (ts - _lastDetectionMs < cooldownMs) {
      _updateWristHistory(result.hands[0], result.hands[1], ts);
      return null;
    }

    final h0 = result.hands[0];
    final h1 = result.hands[1];

    if (h0.landmarks.length < 21 || h1.landmarks.length < 21) return null;

    // --- Pinch: index tips close ---
    final indexDist = _landmarkDist(
      h0.landmarks[HandLandmarkIndex.indexTip],
      h1.landmarks[HandLandmarkIndex.indexTip],
    );
    if (indexDist < pinchThreshold) {
      _lastDetectionMs = ts;
      _updateWristHistory(h0, h1, ts);
      return TwoHandEvent(
        gesture: TwoHandGesture.pinch,
        distance: indexDist,
        timestampMs: ts,
      );
    }

    // --- Clap: wrists approaching fast + fingertips close ---
    final wristDist = _landmarkDist(
      h0.landmarks[HandLandmarkIndex.wrist],
      h1.landmarks[HandLandmarkIndex.wrist],
    );

    final closestFingertip = _closestFingertipDistance(h0, h1);

    if (_prevWristDistance != null && _prevTimestampMs != null) {
      final dtMs = ts - _prevTimestampMs!;
      if (dtMs > 0) {
        final approachSpeed =
            (_prevWristDistance! - wristDist) / (dtMs / 1000.0);
        if (approachSpeed > clapVelocityThreshold &&
            closestFingertip < touchThreshold) {
          _lastDetectionMs = ts;
          _updateWristHistory(h0, h1, ts);
          return TwoHandEvent(
            gesture: TwoHandGesture.clap,
            distance: closestFingertip,
            timestampMs: ts,
          );
        }
      }
    }

    // --- Touching: any fingertips close ---
    if (closestFingertip < touchThreshold) {
      _lastDetectionMs = ts;
      _updateWristHistory(h0, h1, ts);
      return TwoHandEvent(
        gesture: TwoHandGesture.touching,
        distance: closestFingertip,
        timestampMs: ts,
      );
    }

    _updateWristHistory(h0, h1, ts);
    return null;
  }

  void _updateWristHistory(HandResult h0, HandResult h1, int ts) {
    _prevWristDistance = _landmarkDist(
      h0.landmarks[HandLandmarkIndex.wrist],
      h1.landmarks[HandLandmarkIndex.wrist],
    );
    _prevTimestampMs = ts;
  }

  double _closestFingertipDistance(HandResult h0, HandResult h1) {
    var minDist = double.infinity;
    for (final i in _fingertipIndices) {
      for (final j in _fingertipIndices) {
        final d = _landmarkDist(h0.landmarks[i], h1.landmarks[j]);
        if (d < minDist) minDist = d;
      }
    }
    return minDist;
  }

  static double _landmarkDist(NormalizedLandmark a, NormalizedLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Reset detector state.
  void reset() {
    _prevWristDistance = null;
    _prevTimestampMs = null;
    _lastDetectionMs = 0;
  }
}
