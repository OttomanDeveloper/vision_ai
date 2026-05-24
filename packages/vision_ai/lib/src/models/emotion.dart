/// Detected facial emotion types (FER2013 universal emotions).
enum Emotion {
  happy,
  sad,
  angry,
  surprised,
  disgusted,
  fearful,
  neutral,
  // Sent when emotion detection is disabled or confidence is below the threshold.
  none;

  /// Whether an emotion was detected (not [none]).
  bool get isRecognized => this != none;
}
