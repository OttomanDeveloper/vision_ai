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
  final int textureId;
  final bool showHandLandmarks;
  final bool showHandBoundingBox;
  final bool showFaceBoundingBox;
  final bool showFaceContours;
  final bool showGestureLabel;
  final bool showEmotionLabel;
  final OverlayStyle style;
  final Widget Function(BuildContext, VisionResult)? overlayBuilder;
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
        Texture(textureId: textureId),
        StreamBuilder<VisionResult>(
          stream: controller.results,
          builder: (context, snapshot) {
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
                if (overlayBuilder != null) overlayBuilder!(context, result),
              ],
            );
          },
        ),
      ],
    );
  }
}
