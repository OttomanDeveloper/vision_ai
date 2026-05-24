import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

import '../styles/overlay_style.dart';

class EmotionIndicator extends StatelessWidget {
  final FaceResult face;
  final LabelStyle style;

  /// When true, appends the confidence percentage to the emotion name.
  final bool showConfidence;

  const EmotionIndicator({
    super.key,
    required this.face,
    // Blue distinguishes the emotion badge from the gesture badge (dark/default)
    this.style = const LabelStyle(backgroundColor: Colors.blue),
    this.showConfidence = true,
  });

  @override
  Widget build(BuildContext context) {
    // Collapse to nothing when emotion is none/unrecognized — avoids an empty badge
    if (!face.emotion.isRecognized) return const SizedBox.shrink();

    // toStringAsFixed(0) rounds to nearest integer percent — e.g. "87%"
    final confidence = (face.emotionConfidence * 100).toStringAsFixed(0);
    final text = showConfidence
        ? '${_displayName(face.emotion)} $confidence%'
        : _displayName(face.emotion);

    return Container(
      padding: style.padding,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(style.borderRadius),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: style.textColor,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
        ),
      ),
    );
  }

  // Emoji suffix gives quick visual feedback without requiring text comprehension
  static String _displayName(Emotion emotion) => switch (emotion) {
        Emotion.happy => 'HAPPY 😊',
        Emotion.sad => 'SAD 😢',
        Emotion.angry => 'ANGRY 😠',
        Emotion.surprised => 'SURPRISED 😮',
        Emotion.disgusted => 'DISGUSTED 🤢',
        Emotion.fearful => 'FEARFUL 😨',
        Emotion.neutral => 'NEUTRAL 😐',
        Emotion.none => '', // unreachable — guarded by isRecognized above
      };
}
