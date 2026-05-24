import 'dart:collection';
import 'dart:math' as math;

import 'models/face_result.dart';

/// Qualitative attention level derived from the numeric score.
enum AttentionLevel {
  /// Score >= 0.75 — user is focused on the screen.
  high,

  /// Score 0.45–0.75 — partially attentive (glancing away, squinting).
  medium,

  /// Score 0.15–0.45 — mostly disengaged (looking away, eyes closing).
  low,

  /// Score < 0.15 — not paying attention (eyes closed, turned away).
  none,
}

/// Snapshot of attention state for a single frame.
class AttentionScore {
  /// Overall attention score [0.0, 1.0] — weighted combination of components.
  final double score;

  /// Eye openness component [0.0, 1.0]. Average of both eyes.
  final double eyeScore;

  /// Face orientation component [0.0, 1.0]. 1.0 = looking straight at camera.
  final double orientationScore;

  /// Head stability component [0.0, 1.0]. 1.0 = perfectly still.
  final double stabilityScore;

  /// Qualitative level derived from [score].
  final AttentionLevel level;

  const AttentionScore({
    required this.score,
    required this.eyeScore,
    required this.orientationScore,
    required this.stabilityScore,
    required this.level,
  });

  @override
  String toString() =>
      'AttentionScore(${(score * 100).toStringAsFixed(0)}%, ${level.name})';
}

/// Combines eye openness, face orientation, and head stability into a
/// single attention/engagement score.
///
/// All three signals come from [FaceResult] — no extra native processing.
///
/// **Eye openness** — average of left/right eye open probability.
/// Both eyes fully open = 1.0, both closed = 0.0.
///
/// **Face orientation** — how directly the user is facing the camera.
/// Euler angles X (pitch) and Y (yaw) near zero = looking at screen.
/// Angle Z (roll / head tilt) is ignored — tilting your head doesn't
/// mean you stopped paying attention.
///
/// **Head stability** — inverse of angular velocity over a short window.
/// Rapid head movement suggests distraction; stillness suggests focus.
///
/// Usage:
/// ```dart
/// final scorer = AttentionScorer();
///
/// vision.results.listen((result) {
///   final face = result.primaryFace;
///   if (face != null) {
///     final attention = scorer.update(face, result.timestampMs);
///     if (attention != null) {
///       print('Attention: ${attention.score} (${attention.level.name})');
///     }
///   }
/// });
///
/// scorer.reset();
/// ```
class AttentionScorer {
  /// Weight for eye openness in the final score.
  // Eyes carry as much weight as orientation because blinking/drowsiness is a key signal
  final double eyeWeight;

  /// Weight for face orientation in the final score.
  final double orientationWeight;

  /// Weight for head stability in the final score.
  // Lower than the other two — transient motion shouldn't dominate the score
  final double stabilityWeight;

  /// Pitch (X) beyond this angle (degrees) drops orientation score to zero.
  /// 45° covers most "looking away" scenarios without being too strict.
  final double maxPitchDegrees;

  /// Yaw (Y) beyond this angle (degrees) drops orientation score to zero.
  final double maxYawDegrees;

  /// Time window (ms) over which head stability is measured.
  /// Shorter = more responsive but noisier. 500ms is a good balance.
  final int stabilityWindowMs;

  /// Angular velocity (degrees/second) above which stability score is zero.
  /// 60°/s is roughly a quick head turn.
  final double maxAngularVelocity;

  AttentionScorer({
    this.eyeWeight = 0.4,
    this.orientationWeight = 0.4,
    this.stabilityWeight = 0.2,
    this.maxPitchDegrees = 45.0,
    this.maxYawDegrees = 45.0,
    this.stabilityWindowMs = 500,
    this.maxAngularVelocity = 60.0,
  });

  // Ring-buffer of recent angle samples for velocity computation
  final _angleHistory = Queue<_AngleSnapshot>();

  /// Feed a face result and get back an [AttentionScore].
  /// Returns null if eye probabilities are unavailable (face config
  /// doesn't include classifications).
  AttentionScore? update(FaceResult face, int timestampMs) {
    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;
    // Null means the face detector was started without CLASSIFY_ALL option
    if (leftEye == null || rightEye == null) return null;

    // --- Eye openness ---
    // Simple average; partial closures (squinting) reduce the score proportionally
    final eyeScore = ((leftEye + rightEye) / 2.0).clamp(0.0, 1.0);

    // --- Face orientation ---
    // Map pitch and yaw to [0,1]. Angle at 0 = perfect, at max = 0.
    // Multiply rather than average so both axes must be aligned simultaneously
    final pitchNorm =
        (1.0 - (face.headEulerAngleX.abs() / maxPitchDegrees)).clamp(0.0, 1.0);
    final yawNorm =
        (1.0 - (face.headEulerAngleY.abs() / maxYawDegrees)).clamp(0.0, 1.0);
    final orientationScore = pitchNorm * yawNorm;

    // --- Head stability ---
    _angleHistory.addLast(_AngleSnapshot(
      pitch: face.headEulerAngleX,
      yaw: face.headEulerAngleY,
      timestampMs: timestampMs,
    ));

    // Prune samples outside the window
    while (_angleHistory.isNotEmpty &&
        timestampMs - _angleHistory.first.timestampMs > stabilityWindowMs) {
      _angleHistory.removeFirst();
    }

    double stabilityScore = 1.0; // defaults to stable when there's no history yet
    if (_angleHistory.length >= 2) {
      final oldest = _angleHistory.first;
      final newest = _angleHistory.last;
      final dtMs = newest.timestampMs - oldest.timestampMs;
      if (dtMs > 0) {
        final pitchDelta = (newest.pitch - oldest.pitch).abs();
        final yawDelta = (newest.yaw - oldest.yaw).abs();
        // Use max instead of Euclidean distance — a pure yaw turn is as distracting as a diagonal one
        final maxDelta = math.max(pitchDelta, yawDelta);
        final velocity = maxDelta / (dtMs / 1000.0); // degrees per second
        stabilityScore =
            (1.0 - (velocity / maxAngularVelocity)).clamp(0.0, 1.0);
      }
    }

    // --- Weighted combination ---
    // Normalize by totalWeight so arbitrary weight values still produce a [0,1] result
    final totalWeight = eyeWeight + orientationWeight + stabilityWeight;
    final score = ((eyeScore * eyeWeight +
                orientationScore * orientationWeight +
                stabilityScore * stabilityWeight) /
            totalWeight)
        .clamp(0.0, 1.0);

    // Thresholds match the doc-comment ranges on [AttentionLevel]
    final level = switch (score) {
      >= 0.75 => AttentionLevel.high,
      >= 0.45 => AttentionLevel.medium,
      >= 0.15 => AttentionLevel.low,
      _ => AttentionLevel.none,
    };

    return AttentionScore(
      score: score,
      eyeScore: eyeScore,
      orientationScore: orientationScore,
      stabilityScore: stabilityScore,
      level: level,
    );
  }

  /// Reset internal state. Call when switching faces or restarting.
  void reset() {
    _angleHistory.clear();
  }
}

class _AngleSnapshot {
  final double pitch; // degrees, ML Kit Euler X
  final double yaw;   // degrees, ML Kit Euler Y
  final int timestampMs;
  const _AngleSnapshot({
    required this.pitch,
    required this.yaw,
    required this.timestampMs,
  });
}
