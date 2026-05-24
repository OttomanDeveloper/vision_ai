/// Detected facial emotion types (FER2013 universal emotions).
enum Emotion {
  happy,
  sad,
  angry,
  surprised,
  disgusted,
  fearful,
  neutral,
  none;

  /// Whether an emotion was detected (not [none]).
  bool get isRecognized => this != none;
}
