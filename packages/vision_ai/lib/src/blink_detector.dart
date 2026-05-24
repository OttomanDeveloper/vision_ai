import 'models/face_result.dart';

/// Which eye(s) blinked.
enum BlinkEye { left, right, both }

/// Emitted when a blink is detected.
class BlinkEvent {
  /// Which eye(s) blinked.
  final BlinkEye eye;

  /// Duration of the blink in milliseconds (time eyes were closed).
  final int durationMs;

  /// Timestamp when the blink completed (eyes reopened).
  final int timestampMs;

  const BlinkEvent({
    required this.eye,
    required this.durationMs,
    required this.timestampMs,
  });

  @override
  String toString() => 'BlinkEvent($eye, ${durationMs}ms)';
}

/// Detects eye blinks from [FaceResult.leftEyeOpenProbability] and
/// [FaceResult.rightEyeOpenProbability] transitions over time.
///
/// A blink is: eyes open (>openThreshold) → eyes closed (<closedThreshold)
/// → eyes open again, all within [maxBlinkDurationMs].
///
/// Usage:
/// ```dart
/// final blinkDetector = BlinkDetector();
///
/// vision.results.listen((result) {
///   final face = result.primaryFace;
///   if (face != null) {
///     final blink = blinkDetector.update(face, result.timestampMs);
///     if (blink != null) {
///       print('Blinked: ${blink.eye}');
///     }
///   }
/// });
///
/// // Clean up when done
/// blinkDetector.reset();
/// ```
class BlinkDetector {
  /// Eye open probability above this = "eyes open".
  // 0.7 avoids false positives from squinting or partial lighting
  final double openThreshold;

  /// Eye open probability below this = "eyes closed".
  // Gap between thresholds (0.3–0.7) prevents rapid oscillation at the boundary
  final double closedThreshold;

  /// Maximum time (ms) eyes can stay closed and still count as a blink.
  /// Longer closures are ignored (user just closing eyes, not blinking).
  // 500ms covers natural blink range (~100–400ms) with safety margin
  final int maxBlinkDurationMs;

  BlinkDetector({
    this.openThreshold = 0.7,
    this.closedThreshold = 0.3,
    this.maxBlinkDurationMs = 500,
  });

  // State tracking for left eye
  _EyeState _leftState = _EyeState.open;
  int _leftClosedAt = 0; // epoch ms when eye transitioned to closed

  // State tracking for right eye
  _EyeState _rightState = _EyeState.open;
  int _rightClosedAt = 0; // epoch ms when eye transitioned to closed

  /// Feed a face result and get back a [BlinkEvent] if a blink just completed.
  /// Returns null if no blink happened on this frame.
  // Only one event is emitted per frame even if both eyes blink simultaneously
  BlinkEvent? update(FaceResult face, int timestampMs) {
    final leftProb = face.leftEyeOpenProbability;
    final rightProb = face.rightEyeOpenProbability;

    // Probabilities are null when face detection ran without classifications enabled
    if (leftProb == null || rightProb == null) return null;

    final leftBlink = _updateEye(
      leftProb, timestampMs,
      _leftState, _leftClosedAt,
      (s) => _leftState = s,
      (t) => _leftClosedAt = t,
    );

    final rightBlink = _updateEye(
      rightProb, timestampMs,
      _rightState, _rightClosedAt,
      (s) => _rightState = s,
      (t) => _rightClosedAt = t,
    );

    // Both eyes blinked at roughly the same time
    if (leftBlink != null && rightBlink != null) {
      return BlinkEvent(
        eye: BlinkEye.both,
        // Average avoids bias if one eye re-opened a frame before the other
        durationMs: (leftBlink + rightBlink) ~/ 2,
        timestampMs: timestampMs,
      );
    }

    if (leftBlink != null) {
      return BlinkEvent(
        eye: BlinkEye.left,
        durationMs: leftBlink,
        timestampMs: timestampMs,
      );
    }

    if (rightBlink != null) {
      return BlinkEvent(
        eye: BlinkEye.right,
        durationMs: rightBlink,
        timestampMs: timestampMs,
      );
    }

    return null;
  }

  /// Returns blink duration in ms if a blink just completed, null otherwise.
  // Mutation via callbacks keeps each eye's state encapsulated without a class per eye
  int? _updateEye(
    double probability,
    int timestampMs,
    _EyeState currentState,
    int closedAt,
    void Function(_EyeState) setState,
    void Function(int) setClosedAt,
  ) {
    switch (currentState) {
      case _EyeState.open:
        if (probability < closedThreshold) {
          // Eye just closed
          setState(_EyeState.closed);
          setClosedAt(timestampMs);
        }
        return null;

      case _EyeState.closed:
        if (probability > openThreshold) {
          // Eye reopened — blink complete
          setState(_EyeState.open);
          final duration = timestampMs - closedAt;
          if (duration > 0 && duration <= maxBlinkDurationMs) {
            return duration;
          }
          // Too slow — not a blink, just eyes closing
          return null;
        }
        // Check timeout — if closed too long, reset to open state
        // Prevents the detector from locking up if the face disappears mid-blink
        if (timestampMs - closedAt > maxBlinkDurationMs) {
          setState(_EyeState.open);
        }
        return null;
    }
  }

  /// Reset the detector state. Call when switching faces or restarting.
  void reset() {
    _leftState = _EyeState.open;
    _rightState = _EyeState.open;
    _leftClosedAt = 0;
    _rightClosedAt = 0;
  }
}

enum _EyeState { open, closed }
