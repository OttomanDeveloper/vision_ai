import 'dart:collection';

import 'models/face_result.dart';

/// Type of head gesture detected.
enum HeadGesture { nod, shake }

/// Emitted when a head nod or shake is detected.
class HeadGestureEvent {
  final HeadGesture gesture;

  /// Timestamp when the gesture completed.
  final int timestampMs;

  const HeadGestureEvent({
    required this.gesture,
    required this.timestampMs,
  });

  @override
  String toString() => 'HeadGestureEvent(${gesture.name})';
}

/// Detects head nod (yes) and shake (no) from Euler angle oscillations.
///
/// A **nod** is detected when Euler X (pitch / up-down) oscillates past
/// [nodAngleThreshold] degrees at least [minOscillations] times within
/// [windowMs] milliseconds.
///
/// A **shake** is detected when Euler Y (yaw / left-right) oscillates past
/// [shakeAngleThreshold] degrees at least [minOscillations] times within
/// [windowMs] milliseconds.
///
/// Usage:
/// ```dart
/// final headDetector = HeadGestureDetector();
///
/// vision.results.listen((result) {
///   final face = result.primaryFace;
///   if (face != null) {
///     final gesture = headDetector.update(face, result.timestampMs);
///     if (gesture != null) {
///       print(gesture.gesture == HeadGesture.nod ? 'Yes!' : 'No!');
///     }
///   }
/// });
/// ```
class HeadGestureDetector {
  /// Minimum pitch angle change (degrees) to count as an up/down movement.
  final double nodAngleThreshold;

  /// Minimum yaw angle change (degrees) to count as a left/right movement.
  final double shakeAngleThreshold;

  /// Number of direction changes needed to trigger a gesture.
  /// 2 = one back-and-forth cycle, 3 = 1.5 cycles (more reliable).
  final int minOscillations;

  /// Time window (ms) in which oscillations must occur. Slower movements
  /// are ignored (user just looking around, not nodding/shaking).
  final int windowMs;

  /// Cooldown (ms) after a detection before another can fire.
  /// Prevents the same nod/shake from triggering multiple events.
  final int cooldownMs;

  HeadGestureDetector({
    this.nodAngleThreshold = 8.0,
    this.shakeAngleThreshold = 10.0,
    this.minOscillations = 3,
    this.windowMs = 1000,
    this.cooldownMs = 1500,
  });

  // Pitch (nod) tracking
  final _pitchHistory = Queue<_AngleSample>();
  double? _lastPitch;
  int _pitchDirectionChanges = 0;
  bool _pitchGoingUp = false;

  // Yaw (shake) tracking
  final _yawHistory = Queue<_AngleSample>();
  double? _lastYaw;
  int _yawDirectionChanges = 0;
  bool _yawGoingRight = false;

  int _lastDetectionTime = 0;

  /// Feed a face result and get back a [HeadGestureEvent] if a nod or
  /// shake just completed. Returns null if no gesture detected.
  HeadGestureEvent? update(FaceResult face, int timestampMs) {
    // Cooldown — don't detect too frequently
    if (timestampMs - _lastDetectionTime < cooldownMs) {
      _updateAngles(face, timestampMs);
      return null;
    }

    final pitch = face.headEulerAngleX;
    final yaw = face.headEulerAngleY;

    // Track pitch oscillations (nod)
    final nodDetected = _checkOscillation(
      current: pitch,
      previous: _lastPitch,
      threshold: nodAngleThreshold,
      history: _pitchHistory,
      timestampMs: timestampMs,
      directionChanges: _pitchDirectionChanges,
      goingPositive: _pitchGoingUp,
      setDirectionChanges: (v) => _pitchDirectionChanges = v,
      setGoingPositive: (v) => _pitchGoingUp = v,
    );

    // Track yaw oscillations (shake)
    final shakeDetected = _checkOscillation(
      current: yaw,
      previous: _lastYaw,
      threshold: shakeAngleThreshold,
      history: _yawHistory,
      timestampMs: timestampMs,
      directionChanges: _yawDirectionChanges,
      goingPositive: _yawGoingRight,
      setDirectionChanges: (v) => _yawDirectionChanges = v,
      setGoingPositive: (v) => _yawGoingRight = v,
    );

    _lastPitch = pitch;
    _lastYaw = yaw;

    if (nodDetected) {
      _lastDetectionTime = timestampMs;
      _pitchDirectionChanges = 0;
      _pitchHistory.clear();
      return HeadGestureEvent(gesture: HeadGesture.nod, timestampMs: timestampMs);
    }

    if (shakeDetected) {
      _lastDetectionTime = timestampMs;
      _yawDirectionChanges = 0;
      _yawHistory.clear();
      return HeadGestureEvent(gesture: HeadGesture.shake, timestampMs: timestampMs);
    }

    return null;
  }

  bool _checkOscillation({
    required double current,
    required double? previous,
    required double threshold,
    required Queue<_AngleSample> history,
    required int timestampMs,
    required int directionChanges,
    required bool goingPositive,
    required void Function(int) setDirectionChanges,
    required void Function(bool) setGoingPositive,
  }) {
    // Prune old samples outside the time window
    while (history.isNotEmpty &&
        timestampMs - history.first.timestampMs > windowMs) {
      history.removeFirst();
    }

    history.addLast(_AngleSample(current, timestampMs));

    if (previous == null) return false;

    final delta = current - previous;

    // Skip tiny movements (noise)
    if (delta.abs() < 1.0) return false;

    final currentlyGoingPositive = delta > 0;

    if (currentlyGoingPositive != goingPositive) {
      // Direction changed — check if the swing was large enough
      if (history.length >= 2) {
        final recentMin = history.fold<double>(
            history.first.angle, (m, s) => s.angle < m ? s.angle : m);
        final recentMax = history.fold<double>(
            history.first.angle, (m, s) => s.angle > m ? s.angle : m);

        if (recentMax - recentMin >= threshold) {
          setDirectionChanges(directionChanges + 1);
        }
      }
      setGoingPositive(currentlyGoingPositive);
    }

    if (directionChanges + 1 >= minOscillations) {
      return true;
    }

    return false;
  }

  void _updateAngles(FaceResult face, int timestampMs) {
    _lastPitch = face.headEulerAngleX;
    _lastYaw = face.headEulerAngleY;
  }

  /// Reset the detector state.
  void reset() {
    _pitchHistory.clear();
    _yawHistory.clear();
    _lastPitch = null;
    _lastYaw = null;
    _pitchDirectionChanges = 0;
    _yawDirectionChanges = 0;
    _pitchGoingUp = false;
    _yawGoingRight = false;
    _lastDetectionTime = 0;
  }
}

class _AngleSample {
  final double angle;
  final int timestampMs;
  const _AngleSample(this.angle, this.timestampMs);
}
