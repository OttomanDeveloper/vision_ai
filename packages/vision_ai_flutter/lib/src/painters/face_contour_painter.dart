import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

// Contour points are pixel coordinates from ML Kit (same coordinate space as boundingBox),
// packed by FaceDetectionProcessor into a flat array with per-contour size counts.
// The method channel side reconstructs them into List<List<Offset>> before they reach here.
// Each inner list is one contour region (face outline, eyebrow, eye, lip, nose, cheek) drawn as
// an open polyline — ML Kit does not guarantee the contour is closed, so we don't close the path.
class FaceContourPainter extends CustomPainter {
  final List<FaceResult> faces;

  /// Pixel dimensions of the camera image — must match contour point coordinates.
  final Size imageSize;

  /// Fill color for the landmark dots drawn at each contour point.
  final Color dotColor;

  /// Stroke color for the polyline connecting contour points.
  final Color lineColor;

  /// Radius in logical pixels for each contour landmark dot.
  final double dotRadius;

  /// Stroke width in logical pixels for the polyline.
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
    // Guard against imageSize.isEmpty to avoid divide-by-zero in scale computation
    if (faces.isEmpty || imageSize.isEmpty) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round; // reduces jagged corners between short segments

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (final face in faces) {
      // hasContours is false when face detection ran without CONTOUR_ALL mode
      if (!face.hasContours) continue;

      for (final contour in face.contours!) {
        // Single-point contours can't form a line — skip rather than crash
        if (contour.length < 2) continue;

        final path = Path();
        final first = _scale(contour[0], scaleX, scaleY);
        path.moveTo(first.dx, first.dy);

        for (var i = 1; i < contour.length; i++) {
          final pt = _scale(contour[i], scaleX, scaleY);
          path.lineTo(pt.dx, pt.dy);
        }

        // Draw line first so dots render on top of it at each point
        canvas.drawPath(path, linePaint);

        for (final pt in contour) {
          final scaled = _scale(pt, scaleX, scaleY);
          canvas.drawCircle(scaled, dotRadius, dotPaint);
        }
      }
    }
  }

  // Applies independent X/Y scale to handle non-square camera-to-canvas ratios
  Offset _scale(Offset pt, double sx, double sy) =>
      Offset(pt.dx * sx, pt.dy * sy);

  @override
  // Identity check is intentional — a new List instance always triggers repaint
  bool shouldRepaint(FaceContourPainter oldDelegate) =>
      !identical(faces, oldDelegate.faces);
}
