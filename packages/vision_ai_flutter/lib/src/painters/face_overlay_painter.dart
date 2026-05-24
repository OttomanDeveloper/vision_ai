import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

// Bounding box coordinates are in pixels relative to the camera frame (imageSize),
// not normalized. ML Kit returns absolute pixel values, so we scale to canvas size here.
// imageSize comes from VisionResult and changes if the camera resolution changes mid-session.
class FaceOverlayPainter extends CustomPainter {
  final List<FaceResult> faces;
  final Color boxColor;
  final double boxWidth;
  final Size imageSize;

  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    this.boxColor = Colors.cyan,
    this.boxWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty || imageSize.isEmpty) return;

    final paint = Paint()
      ..color = boxColor
      ..strokeWidth = boxWidth
      ..style = PaintingStyle.stroke;

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
  bool shouldRepaint(FaceOverlayPainter oldDelegate) =>
      !identical(faces, oldDelegate.faces);
}
