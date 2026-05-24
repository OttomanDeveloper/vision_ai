import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

import '../styles/overlay_style.dart';

class EmotionIndicator extends StatelessWidget {
  final FaceResult face;
  final LabelStyle style;
  final bool showConfidence;

  const EmotionIndicator({
    super.key,
    required this.face,
    this.style = const LabelStyle(backgroundColor: Colors.blue),
    this.showConfidence = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!face.emotion.isRecognized) return const SizedBox.shrink();

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

  static String _displayName(Emotion emotion) => switch (emotion) {
        Emotion.happy => 'HAPPY 😊',
        Emotion.sad => 'SAD 😢',
        Emotion.angry => 'ANGRY 😠',
        Emotion.surprised => 'SURPRISED 😮',
        Emotion.disgusted => 'DISGUSTED 🤢',
        Emotion.fearful => 'FEARFUL 😨',
        Emotion.neutral => 'NEUTRAL 😐',
        Emotion.none => '',
      };
}
