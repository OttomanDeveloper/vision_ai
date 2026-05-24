import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

import '../styles/overlay_style.dart';

class GestureLabel extends StatelessWidget {
  final HandResult hand;
  final LabelStyle style;

  const GestureLabel({
    super.key,
    required this.hand,
    this.style = const LabelStyle(),
  });

  @override
  Widget build(BuildContext context) {
    if (!hand.gesture.isRecognized) return const SizedBox.shrink();

    final text = hand.gesture == Gesture.custom
        ? (hand.customGestureName ?? 'CUSTOM').toUpperCase()
        : _displayName(hand.gesture);

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

  static String _displayName(Gesture gesture) => switch (gesture) {
        Gesture.fist => 'FIST',
        Gesture.openHand => 'OPEN HAND',
        Gesture.peace => 'PEACE',
        Gesture.thumbsUp => 'THUMBS UP',
        Gesture.thumbsDown => 'THUMBS DOWN',
        Gesture.pointingUp => 'POINTING',
        Gesture.ok => 'OK',
        Gesture.iLoveYou => 'I LOVE YOU',
        Gesture.one => 'ONE',
        Gesture.two => 'TWO',
        Gesture.three => 'THREE',
        Gesture.four => 'FOUR',
        Gesture.five => 'FIVE',
        Gesture.custom => 'CUSTOM',
        Gesture.none => '',
      };
}
