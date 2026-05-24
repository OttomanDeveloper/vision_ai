import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

import '../styles/overlay_style.dart';

// Hand landmarks are normalized [0,1] in the camera frame. The Texture widget stretches to fill
// its box with no letterboxing, so we map directly to canvas size without aspect-ratio correction.
// If the preview is letterboxed in the future, _toCanvas will need to account for the offset.
// Mirror flag should match the camera facing: front camera output is already mirrored on Android
// so set mirrorLandmarks=true only when the Texture itself is NOT flipped.
class HandLandmarkPainter extends CustomPainter {
  final List<HandResult> hands;
  final LandmarkStyle style;
  final bool mirrored;
  final Size imageSize;

  HandLandmarkPainter({
    required this.hands,
    required this.imageSize,
    this.style = const LandmarkStyle(),
    this.mirrored = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    final linePaint = Paint()
      ..color = style.lineColor
      ..strokeWidth = style.lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = style.dotColor
      ..style = PaintingStyle.fill;

    for (final hand in hands) {
      if (hand.landmarks.isEmpty) continue;

      for (final connection in HandLandmarkIndex.connections) {
        final from = connection[0];
        final to = connection[1];
        if (from >= hand.landmarks.length || to >= hand.landmarks.length) {
          continue;
        }

        final p1 = _toCanvas(hand.landmarks[from], size);
        final p2 = _toCanvas(hand.landmarks[to], size);
        canvas.drawLine(p1, p2, linePaint);
      }

      for (final landmark in hand.landmarks) {
        final point = _toCanvas(landmark, size);
        canvas.drawCircle(point, style.dotRadius, dotPaint);
      }
    }
  }

  Offset _toCanvas(NormalizedLandmark landmark, Size size) {
    // Landmarks are normalized [0,1]. Texture widget stretches to fill,
    // so we map directly to canvas dimensions.
    final x = mirrored
        ? (1.0 - landmark.x) * size.width
        : landmark.x * size.width;
    final y = landmark.y * size.height;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(HandLandmarkPainter oldDelegate) =>
      !identical(hands, oldDelegate.hands);
}
