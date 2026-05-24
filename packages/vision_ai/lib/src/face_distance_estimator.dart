import 'dart:math' as math;
import 'dart:ui' show Size;

import 'models/face_result.dart';

/// Estimated distance of a face from the camera.
class FaceDistanceEstimate {
  /// Approximate distance in centimeters. This is a rough estimate based
  /// on face bounding box size relative to image dimensions. Accuracy
  /// depends on the person's actual face width and camera field of view.
  final double distanceCm;

  /// How much of the image width the face occupies [0.0, 1.0].
  /// Closer to 1.0 = face fills the frame (very close).
  /// Closer to 0.0 = face is a small portion (far away).
  final double faceRatio;

  /// Qualitative distance category for simpler usage.
  final FaceDistanceZone zone;

  const FaceDistanceEstimate({
    required this.distanceCm,
    required this.faceRatio,
    required this.zone,
  });

  @override
  String toString() =>
      'FaceDistanceEstimate(${distanceCm.toStringAsFixed(0)}cm, ${zone.name})';
}

/// Qualitative distance zones.
enum FaceDistanceZone {
  /// Face fills >40% of frame. Roughly <30cm.
  veryClose,

  /// Face fills 20-40% of frame. Roughly 30-60cm.
  close,

  /// Face fills 10-20% of frame. Roughly 60-120cm.
  medium,

  /// Face fills <10% of frame. Roughly >120cm.
  far,
}

/// Estimates how far a face is from the camera using bounding box size.
///
/// This is a geometric approximation, not a depth measurement. It assumes
/// an average adult face width of ~15cm and a typical phone camera FOV.
/// Accuracy is ±20-30% — useful for "near/far" decisions, not precise
/// measurement.
///
/// Usage:
/// ```dart
/// final distanceEstimator = FaceDistanceEstimator();
///
/// vision.results.listen((result) {
///   final face = result.primaryFace;
///   if (face != null) {
///     final estimate = distanceEstimator.estimate(face, result.imageSize);
///     print('${estimate.distanceCm}cm (${estimate.zone.name})');
///   }
/// });
/// ```
class FaceDistanceEstimator {
  /// Assumed real-world face width in centimeters.
  /// Average adult face is ~14-16cm. Adjust for your use case.
  final double assumedFaceWidthCm;

  /// Assumed horizontal field of view of the camera in degrees.
  /// Most phone front cameras are 70-80°. Back cameras vary more.
  final double cameraFovDegrees;

  FaceDistanceEstimator({
    this.assumedFaceWidthCm = 15.0,
    this.cameraFovDegrees = 75.0,
  });

  /// Estimate distance from a face result and the camera image size.
  /// Returns null if the bounding box has zero width.
  FaceDistanceEstimate? estimate(FaceResult face, Size imageSize) {
    if (imageSize.width <= 0) return null;

    final faceWidthPx = face.boundingBox.width;
    if (faceWidthPx <= 0) return null;

    final faceRatio = faceWidthPx / imageSize.width;

    // Pinhole camera model:
    // distance = (realWidth * imageWidth) / (2 * faceWidthPx * tan(fov/2))
    //
    // Simplified since faceRatio = faceWidthPx / imageWidth:
    // distance = realWidth / (2 * faceRatio * tan(fov/2))
    final halfFovRad = (cameraFovDegrees / 2) * math.pi / 180;
    final tanHalfFov = math.tan(halfFovRad);

    final distanceCm = assumedFaceWidthCm / (2 * faceRatio * tanHalfFov);

    final zone = switch (faceRatio) {
      > 0.4 => FaceDistanceZone.veryClose,
      > 0.2 => FaceDistanceZone.close,
      > 0.1 => FaceDistanceZone.medium,
      _ => FaceDistanceZone.far,
    };

    return FaceDistanceEstimate(
      distanceCm: distanceCm,
      faceRatio: faceRatio.clamp(0.0, 1.0),
      zone: zone,
    );
  }

}
