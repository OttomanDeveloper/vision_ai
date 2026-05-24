import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A 3D point in normalized image coordinates where x and y are in [0.0, 1.0]
/// relative to the image dimensions. Z represents depth relative to the wrist
/// (negative = closer to camera). Used for [HandResult.landmarks].
class NormalizedLandmark {
  final double x;
  final double y;
  final double z;

  const NormalizedLandmark(this.x, this.y, this.z);

  /// Convert to a 2D canvas point by scaling to pixel dimensions.
  Offset toOffset(double width, double height) =>
      Offset(x * width, y * height);

  @override
  String toString() => 'NormalizedLandmark($x, $y, $z)';
}

/// A 3D point in real-world coordinates where x, y, and z are in **meters**.
/// Origin is the hand's geometric center. Used for [HandResult.worldLandmarks].
///
/// Unlike [NormalizedLandmark], these values are scale-accurate — the distance
/// between two [WorldLandmark] points corresponds to a physical measurement.
/// Use [distanceTo] to measure real distances (e.g., hand span, pinch gap).
class WorldLandmark {
  /// Horizontal position in meters (positive = right from hand center).
  final double x;

  /// Vertical position in meters (positive = up from hand center).
  final double y;

  /// Depth position in meters (positive = away from camera).
  final double z;

  const WorldLandmark(this.x, this.y, this.z);

  /// Euclidean distance to another world landmark in meters.
  double distanceTo(WorldLandmark other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  @override
  String toString() => 'WorldLandmark($x, $y, $z)';
}

/// MediaPipe hand model produces exactly 21 landmarks per hand.
/// The topology here mirrors the MediaPipe Hand landmark documentation:
/// 0=wrist, 1-4=thumb (CMC→tip), 5-8=index, 9-12=middle, 13-16=ring, 17-20=pinky.
/// The [connections] list drives skeleton rendering and must stay in sync with
/// how the Kotlin side packs the flat DoubleArray (index * 3 = x, +1 = y, +2 = z).
/// Indices and topology for the 21 hand landmark points.
abstract class HandLandmarkIndex {
  static const int wrist = 0;
  static const int thumbCmc = 1;
  static const int thumbMcp = 2;
  static const int thumbIp = 3;
  static const int thumbTip = 4;
  static const int indexMcp = 5;
  static const int indexPip = 6;
  static const int indexDip = 7;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int middlePip = 10;
  static const int middleDip = 11;
  static const int middleTip = 12;
  static const int ringMcp = 13;
  static const int ringPip = 14;
  static const int ringDip = 15;
  static const int ringTip = 16;
  static const int pinkyMcp = 17;
  static const int pinkyPip = 18;
  static const int pinkyDip = 19;
  static const int pinkyTip = 20;

  static const int count = 21;

  static const List<List<int>> connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // Index
    [0, 9], [9, 10], [10, 11], [11, 12], // Middle
    [0, 13], [13, 14], [14, 15], [15, 16], // Ring
    [0, 17], [17, 18], [18, 19], [19, 20], // Pinky
    [5, 9], [9, 13], [13, 17], // Palm
  ];
}
