import 'package:flutter/material.dart';
import 'package:vision_ai/vision_ai.dart';

import '../painters/face_contour_painter.dart';
import '../painters/face_overlay_painter.dart';
import '../painters/hand_bounding_box_painter.dart';
import '../painters/hand_landmark_painter.dart';
import '../styles/overlay_style.dart';
import 'emotion_indicator.dart';
import 'gesture_label.dart';

// StreamBuilder drives all overlays from the same result stream so every layer stays in sync
// with a single frame — no risk of hand landmarks being one frame ahead of face boxes.
// overlayBuilder exists for callers who need full VisionResult access (e.g. custom UI, game logic)
// without subclassing this widget or reimplementing the stream subscription themselves.
class VisionAiCameraView extends StatelessWidget {
  final VisionAi controller;

  /// Platform texture ID returned by the native camera setup call.
  final int textureId;

  /// Show the 21-point skeleton on each detected hand.
  final bool showHandLandmarks;

  /// Show a bounding rectangle around each detected hand.
  // Off by default — landmarks already convey hand position and are less cluttered
  final bool showHandBoundingBox;

  /// Show a bounding rectangle around each detected face.
  final bool showFaceBoundingBox;

  /// Show per-face contour dot overlay. Requires CONTOUR_ALL detection mode.
  // Off by default — enabling it alongside face bounding boxes can look noisy
  final bool showFaceContours;

  /// Show the recognized gesture name above the frame.
  final bool showGestureLabel;

  /// Show the detected emotion name below the frame.
  final bool showEmotionLabel;

  /// Visual style applied to all overlays. Use [OverlayStyle] defaults for quick setup.
  final OverlayStyle style;

  /// Optional escape hatch — receives the full [VisionResult] and can render any widget.
  // Rendered last so it sits above all built-in overlays in the Stack
  final Widget Function(BuildContext, VisionResult)? overlayBuilder;

  /// When true, landmark and bounding box positions are flipped horizontally.
  // Set to true for front camera when the native Texture is not already mirrored
  final bool mirrorLandmarks;

  const VisionAiCameraView({
    super.key,
    required this.controller,
    required this.textureId,
    this.showHandLandmarks = true,
    this.showHandBoundingBox = false,
    this.showFaceBoundingBox = true,
    this.showFaceContours = false,
    this.showGestureLabel = true,
    this.showEmotionLabel = true,
    this.style = const OverlayStyle(),
    this.overlayBuilder,
    this.mirrorLandmarks = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview — renders the platform texture at whatever size the Stack provides
        Texture(textureId: textureId),
        StreamBuilder<VisionResult>(
          stream: controller.results,
          builder: (context, snapshot) {
            // Don't paint overlays until the first result arrives
            final result = snapshot.data;
            if (result == null) return const SizedBox.shrink();

            return Stack(
              fit: StackFit.expand,
              children: [
                if (showHandLandmarks && result.hasHands)
                  CustomPaint(
                    painter: HandLandmarkPainter(
                      hands: result.hands,
                      imageSize: result.imageSize,
                      style: style.handLandmark,
                      mirrored: mirrorLandmarks,
                    ),
                  ),
                if (showHandBoundingBox && result.hasHands)
                  CustomPaint(
                    painter: HandBoundingBoxPainter(
                      hands: result.hands,
                      boxColor: style.handBoundingBoxColor,
                      boxWidth: style.handBoundingBoxWidth,
                      mirrored: mirrorLandmarks,
                    ),
                  ),
                if (showFaceBoundingBox && result.hasFaces)
                  CustomPaint(
                    painter: FaceOverlayPainter(
                      faces: result.faces,
                      imageSize: result.imageSize,
                      boxColor: style.faceBoundingBoxColor,
                      boxWidth: style.faceBoundingBoxWidth,
                    ),
                  ),
                if (showFaceContours && result.hasFaces)
                  CustomPaint(
                    painter: FaceContourPainter(
                      faces: result.faces,
                      imageSize: result.imageSize,
                    ),
                  ),
                if (showGestureLabel && result.primaryHand != null)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureLabel(
                        hand: result.primaryHand!,
                        style: style.gestureLabel,
                      ),
                    ),
                  ),
                if (showEmotionLabel && result.primaryFace != null)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: EmotionIndicator(
                        face: result.primaryFace!,
                        style: style.emotionLabel,
                        showConfidence: style.showEmotionConfidence,
                      ),
                    ),
                  ),
                // Custom overlay is always last so it can overdraw built-in widgets
                if (overlayBuilder != null) overlayBuilder!(context, result),
              ],
            );
          },
        ),
      ],
    );
  }
}
