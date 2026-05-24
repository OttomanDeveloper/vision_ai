import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

// Bounding box coordinates are in pixels relative to the camera frame (imageSize),
// not normalized. ML Kit returns absolute pixel values, so we scale to canvas size here.
// imageSize comes from VisionResult and changes if the camera resolution changes mid-session.
class FaceOverlayPainter extends CustomPainter {
  final List<FaceResult> faces;

  /// Stroke color for the bounding rectangle.
  final Color boxColor;

  /// Stroke width in logical pixels.
  final double boxWidth;

  /// Pixel dimensions of the camera image — must match the coordinate space of boundingBox.
  final Size imageSize;

  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    this.boxColor = Colors.cyan,
    this.boxWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Guard against imageSize.isEmpty to avoid divide-by-zero in scale computation
    if (faces.isEmpty || imageSize.isEmpty) return;

    final paint = Paint()
      ..color = boxColor
      ..strokeWidth = boxWidth
      ..style = PaintingStyle.stroke;

    // Scale factors convert pixel coordinates to canvas logical pixels
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final face in faces) {
      final rect = Rect.fromLTRB(
        face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  // Identity check is intentional — a new List instance always triggers repaint
  bool shouldRepaint(FaceOverlayPainter oldDelegate) =>
      !identical(faces, oldDelegate.faces);
}
