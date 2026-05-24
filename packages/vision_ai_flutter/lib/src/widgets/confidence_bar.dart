import 'package:flutter/material.dart';

class ConfidenceBar extends StatelessWidget {
  /// Confidence value in [0.0, 1.0]. Values outside this range are clamped.
  final double value;

  /// Optional text label rendered to the left of the bar.
  final String? label;

  /// Color of the filled portion of the bar.
  // Green default signals "good/high confidence" intuitively
  final Color activeColor;

  /// Color of the unfilled track behind the bar.
  final Color inactiveColor;

  /// Bar height in logical pixels. Also controls the corner radius (height / 2).
  final double height;

  /// Total bar width in logical pixels (label and percentage text are outside this).
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
            // Pill shape — radius = half height makes a perfect semicircle cap
            borderRadius: BorderRadius.circular(height / 2),
            child: LinearProgressIndicator(
              // Clamp here so callers don't have to — values like 1.001 from float math are safe
              value: value.clamp(0.0, 1.0),
              // Low alpha on the track keeps focus on the active portion
              backgroundColor: inactiveColor.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(activeColor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          // toStringAsFixed(0) produces clean integers like "87%" instead of "87.3%"
          '${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
      ],
    );
  }
}
