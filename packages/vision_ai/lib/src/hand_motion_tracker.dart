import 'dart:collection';
import 'dart:math' as math;

import 'models/hand_result.dart';

/// Qualitative speed category.
enum HandMotionState {
  /// Speed < 0.02 norm/s — hand is essentially still.
  still,

  /// Speed 0.02–0.15 norm/s — slow deliberate movement.
  slow,

  /// Speed 0.15–0.5 norm/s — normal movement.
  moderate,

  /// Speed > 0.5 norm/s — fast swipe or wave.
  fast,
}

/// Direction of hand movement, bucketed into 8 compass directions.
enum HandDirection { up, upRight, right, downRight, down, downLeft, left, upLeft }

/// Snapshot of hand motion for a single frame.
class HandMotion {
  /// Speed in normalized image units per second. 1.0 means the hand
  /// crossed the full image width in one second.
  final double speed;

  /// Movement direction as an angle in radians. 0 = right, pi/2 = down,
  /// -pi/2 = up, pi = left. Follows screen coordinate convention (Y down).
  final double directionRadians;

  /// Movement direction bucketed into 8 compass points.
  final HandDirection direction;

  /// Qualitative speed category.
  final HandMotionState state;

  /// Horizontal velocity component (normalized units/sec, positive = right).
  final double velocityX;

  /// Vertical velocity component (normalized units/sec, positive = down).
  final double velocityY;

  const HandMotion({
    required this.speed,
    required this.directionRadians,
    required this.direction,
    required this.state,
    required this.velocityX,
    required this.velocityY,
  });

  @override
  String toString() =>
      'HandMotion(${speed.toStringAsFixed(2)}/s, ${direction.name}, ${state.name})';
}

/// Tracks hand position across frames to compute velocity and direction.
///
/// Uses the wrist landmark (index 0) as the hand's reference point.
/// Smooths velocity over [windowMs] to reduce per-frame jitter.
///
/// Usage:
/// ```dart
/// final tracker = HandMotionTracker();
///
/// vision.results.listen((result) {
///   final hand = result.primaryHand;
///   if (hand != null) {
///     final motion = tracker.update(hand, result.timestampMs);
///     if (motion != null) {
///       print('${motion.speed} ${motion.direction.name}');
///     }
///   }
/// });
///
/// tracker.reset();
/// ```
class HandMotionTracker {
  /// Time window (ms) over which velocity is averaged.
  // 200ms balances responsiveness with jitter suppression at typical 30fps
  final int windowMs;

  /// Speed below this threshold (norm/s) is reported as [HandMotionState.still].
  // 0.02 norm/s ≈ 2% of image width per second — filters tracker noise at rest
  final double stillThreshold;

  /// Landmark index to track. Default 0 = wrist.
  // Wrist is the most stable landmark; fingertips jitter more during gestures
  final int trackingLandmarkIndex;

  HandMotionTracker({
    this.windowMs = 200,
    this.stillThreshold = 0.02,
    this.trackingLandmarkIndex = 0,
  });

  // Sliding window of recent positions; oldest sample beyond windowMs is pruned each frame
  final _history = Queue<_PositionSample>();

  /// Feed a hand result and get back a [HandMotion].
  /// Returns null on the first frame or if landmarks are missing.
  HandMotion? update(HandResult hand, int timestampMs) {
    if (hand.landmarks.length <= trackingLandmarkIndex) return null;

    final lm = hand.landmarks[trackingLandmarkIndex];
    _history.addLast(_PositionSample(lm.x, lm.y, timestampMs));

    // Prune old samples
    while (_history.isNotEmpty &&
        timestampMs - _history.first.timestampMs > windowMs) {
      _history.removeFirst();
    }

    // Need at least two points to compute velocity
    if (_history.length < 2) return null;

    final oldest = _history.first;
    final newest = _history.last;
    final dtMs = newest.timestampMs - oldest.timestampMs;
    if (dtMs <= 0) return null;

    final dtSec = dtMs / 1000.0; // convert ms to seconds for units consistency
    final dx = newest.x - oldest.x; // normalized units, positive = right
    final dy = newest.y - oldest.y; // normalized units, positive = down

    final vx = dx / dtSec;
    final vy = dy / dtSec;
    final speed = math.sqrt(vx * vx + vy * vy);

    // atan2 with (dy, dx) gives angle in screen space where Y increases downward
    final angle = math.atan2(dy, dx);
    final dir = _bucketDirection(angle);

    // Thresholds match the doc-comment ranges on [HandMotionState]
    final state = switch (speed) {
      < 0.02 => HandMotionState.still,
      < 0.15 => HandMotionState.slow,
      < 0.5 => HandMotionState.moderate,
      _ => HandMotionState.fast,
    };

    return HandMotion(
      speed: speed,
      directionRadians: angle,
      direction: dir,
      state: state,
      velocityX: vx,
      velocityY: vy,
    );
  }

  // Maps a radian angle to one of 8 45°-wide compass sectors
  static HandDirection _bucketDirection(double radians) {
    // Normalize to [0, 2*pi)
    final a = (radians + 2 * math.pi) % (2 * math.pi);
    // 8 sectors of 45° each, offset by 22.5° so "right" is centered on 0°
    final sector = ((a + math.pi / 8) / (math.pi / 4)).floor() % 8;
    return switch (sector) {
      0 => HandDirection.right,
      1 => HandDirection.downRight,
      2 => HandDirection.down,
      3 => HandDirection.downLeft,
      4 => HandDirection.left,
      5 => HandDirection.upLeft,
      6 => HandDirection.up,
      7 => HandDirection.upRight,
      _ => HandDirection.right, // unreachable after % 8, satisfies exhaustiveness
    };
  }

  /// Reset tracking state. Call when the hand is lost or on restart.
  void reset() {
    _history.clear();
  }
}

class _PositionSample {
  final double x; // normalized [0,1], landmark.x
  final double y; // normalized [0,1], landmark.y
  final int timestampMs;
  const _PositionSample(this.x, this.y, this.timestampMs);
}
