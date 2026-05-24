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
  custom,
  none;

  bool get isRecognized => this != none;
}
