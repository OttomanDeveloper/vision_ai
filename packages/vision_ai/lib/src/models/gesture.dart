/// Recognized hand gesture types.
enum Gesture {
  fist,
  openHand,
  peace,
  thumbsUp,
  thumbsDown,
  pointingUp,
  ok,
  iLoveYou,
  one,
  two,
  three,
  four,
  five,
  /// A user-defined custom gesture. Check [HandResult.customGestureName].
  custom,
  // Sent when no gesture is confidently matched; may still carry landmark data.
  none;

  /// Whether a gesture was detected (not [none]).
  bool get isRecognized => this != none;
}
