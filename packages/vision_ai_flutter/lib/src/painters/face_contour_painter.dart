import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

// Contour points are pixel coordinates from ML Kit (same coordinate space as boundingBox),
// packed by FaceDetectionProcessor into a flat array with per-contour size counts.
// The method channel side reconstructs them into List<List<Offset>> before they reach here.
// Each inner list is one contour region (face outline, eyebrow, eye, lip, nose) drawn as
// an open polyline — ML Kit does not guarantee the contour is closed, so we don't close the path.
class FaceContourPainter extends CustomPainter {
  final List<FaceResult> faces;
  final Size imageSize;
  final Color dotColor;
  final Color lineColor;
  final double dotRadius;
  final double lineWidth;

  FaceContourPainter({
    required this.faces,
    required this.imageSize,
    this.dotColor = Colors.greenAccent,
    this.lineColor = Colors.greenAccent,
    this.dotRadius = 2.0,
    this.lineWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty || imageSize.isEmpty) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (final face in faces) {
      if (!face.hasContours) continue;

      for (final contour in face.contours!) {
        if (contour.length < 2) continue;

        final path = Path();
        final first = _scale(contour[0], scaleX, scaleY);
        path.moveTo(first.dx, first.dy);

        for (var i = 1; i < contour.length; i++) {
          final pt = _scale(contour[i], scaleX, scaleY);
          path.lineTo(pt.dx, pt.dy);
        }

        canvas.drawPath(path, linePaint);

        for (final pt in contour) {
          final scaled = _scale(pt, scaleX, scaleY);
          canvas.drawCircle(scaled, dotRadius, dotPaint);
        }
      }
    }
  }

  Offset _scale(Offset pt, double sx, double sy) =>
      Offset(pt.dx * sx, pt.dy * sy);

  @override
  bool shouldRepaint(FaceContourPainter oldDelegate) =>
      !identical(faces, oldDelegate.faces);
}
