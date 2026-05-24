import 'package:flutter/material.dart';

/// Top-level style bundle passed to [VisionAiCameraView].
/// Groups all sub-styles so callers pass one object instead of many parameters.
class OverlayStyle {
  /// Style for the 21-landmark hand skeleton lines and dots.
  final LandmarkStyle handLandmark;

  /// Style for the gesture name badge shown above the frame.
  final LabelStyle gestureLabel;

  /// Style for the emotion name badge shown below the frame.
  // Separate from gestureLabel so they can use different background colors
  final LabelStyle emotionLabel;

  /// Stroke color for the hand bounding rectangle.
  // Yellow chosen to contrast against both light and dark skin tones
  final Color handBoundingBoxColor;

  /// Stroke width in logical pixels for the hand bounding rectangle.
  final double handBoundingBoxWidth;

  /// Stroke color for the face bounding rectangle.
  // Cyan contrasts with yellow so face and hand boxes are visually distinct
  final Color faceBoundingBoxColor;

  /// Stroke width in logical pixels for the face bounding rectangle.
  final double faceBoundingBoxWidth;

  /// When true, [EmotionIndicator] appends the confidence percentage.
  final bool showEmotionConfidence;

  const OverlayStyle({
    this.handLandmark = const LandmarkStyle(),
    this.gestureLabel = const LabelStyle(),
    this.emotionLabel = const LabelStyle(
      backgroundColor: Colors.blue,
    ),
    this.handBoundingBoxColor = Colors.yellow,
    this.handBoundingBoxWidth = 2.0,
    this.faceBoundingBoxColor = Colors.cyan,
    this.faceBoundingBoxWidth = 2.0,
    this.showEmotionConfidence = true,
  });
}

/// Visual style for the 21-point hand landmark skeleton.
class LandmarkStyle {
  /// Fill color for each landmark dot.
  // Red is easy to spot against skin tones and green skeleton lines
  final Color dotColor;

  /// Stroke color for the bone connection lines.
  // Green pairs with red dots to create a clear point-and-line visual hierarchy
  final Color lineColor;

  /// Dot radius in logical pixels.
  // 4.0 is large enough to tap but not so large it obscures the underlying hand
  final double dotRadius;

  /// Line stroke width in logical pixels.
  final double lineWidth;

  const LandmarkStyle({
    this.dotColor = Colors.red,
    this.lineColor = Colors.green,
    this.dotRadius = 4.0,
    this.lineWidth = 2.0,
  });
}

/// Visual style for floating label badges (gesture name, emotion name).
class LabelStyle {
  /// Text color inside the badge.
  final Color textColor;

  /// Badge background fill color.
  // Dark default ensures legibility over any camera background
  final Color backgroundColor;

  /// Font size in logical pixels.
  // 20sp is large enough to read from arm's length at typical phone resolution
  final double fontSize;

  /// Font weight for the label text.
  final FontWeight fontWeight;

  /// Corner radius in logical pixels — applied uniformly to all corners.
  final double borderRadius;

  /// Internal padding between text and badge edge.
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
