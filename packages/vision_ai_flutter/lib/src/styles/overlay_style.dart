import 'package:flutter/material.dart';

class OverlayStyle {
  final LandmarkStyle handLandmark;
  final LabelStyle gestureLabel;
  final LabelStyle emotionLabel;
  final Color faceBoundingBoxColor;
  final double faceBoundingBoxWidth;
  final bool showEmotionConfidence;

  const OverlayStyle({
    this.handLandmark = const LandmarkStyle(),
    this.gestureLabel = const LabelStyle(),
    this.emotionLabel = const LabelStyle(
      backgroundColor: Colors.blue,
    ),
    this.faceBoundingBoxColor = Colors.cyan,
    this.faceBoundingBoxWidth = 2.0,
    this.showEmotionConfidence = true,
  });
}

class LandmarkStyle {
  final Color dotColor;
  final Color lineColor;
  final double dotRadius;
  final double lineWidth;

  const LandmarkStyle({
    this.dotColor = Colors.red,
    this.lineColor = Colors.green,
    this.dotRadius = 4.0,
    this.lineWidth = 2.0,
  });
}

class LabelStyle {
  final Color textColor;
  final Color backgroundColor;
  final double fontSize;
  final FontWeight fontWeight;
  final double borderRadius;
  final EdgeInsets padding;

  const LabelStyle({
    this.textColor = Colors.white,
    this.backgroundColor = Colors.black87,
    this.fontSize = 20.0,
    this.fontWeight = FontWeight.bold,
    this.borderRadius = 12.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });
}
