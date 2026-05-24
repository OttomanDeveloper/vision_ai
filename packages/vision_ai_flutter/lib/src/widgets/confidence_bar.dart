import 'package:flutter/material.dart';

class ConfidenceBar extends StatelessWidget {
  final double value;
  final String? label;
  final Color activeColor;
  final Color inactiveColor;
  final double height;
  final double width;

  const ConfidenceBar({
    super.key,
    required this.value,
    this.label,
    this.activeColor = Colors.greenAccent,
    this.inactiveColor = Colors.grey,
    this.height = 8.0,
    this.width = 120.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
          ),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: inactiveColor.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(activeColor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
      ],
    );
  }
}
