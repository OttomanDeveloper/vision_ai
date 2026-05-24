import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

// Hand bounding box is computed from normalized [0,1] landmarks, not pixel
// coordinates like the face bounding box. We map directly to canvas size
// (same as HandLandmarkPainter) since Texture stretches to fill its box.
class HandBoundingBoxPainter extends CustomPainter {
  final List<HandResult> hands;
  final Color boxColor;
  final double boxWidth;
  final bool mirrored;

  HandBoundingBoxPainter({
    required this.hands,
    this.boxColor = Colors.yellow,
    this.boxWidth = 2.0,
    this.mirrored = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    final paint = Paint()
      ..color = boxColor
      ..strokeWidth = boxWidth
      ..style = PaintingStyle.stroke;

    for (final hand in hands) {
      final bbox = hand.boundingBox;
      if (bbox == null) continue;

      final left = mirrored ? (1.0 - bbox.right) : bbox.left;
      final right = mirrored ? (1.0 - bbox.left) : bbox.right;

      final rect = Rect.fromLTRB(
        left * size.width,
        bbox.top * size.height,
        right * size.width,
        bbox.bottom * size.height,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(HandBoundingBoxPainter oldDelegate) =>
      !identical(hands, oldDelegate.hands);
}
