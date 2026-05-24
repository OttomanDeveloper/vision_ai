enum Emotion {
  happy,
  sad,
  angry,
  surprised,
  disgusted,
  fearful,
  neutral,
  none;

  bool get isRecognized => this != none;
}
