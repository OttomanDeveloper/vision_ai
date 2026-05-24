/// The five fingers of a hand.
enum Finger { thumb, indexFinger, middle, ring, pinky }

/// Whether a finger is extended (up) or closed (curled).
// Only two states are surfaced to Dart; the native -1 wildcard is config-only.
enum FingerState { extended, closed }
