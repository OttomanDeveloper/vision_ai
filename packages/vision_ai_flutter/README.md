# vision_ai_flutter

Pre-built Flutter UI overlay widgets for [vision_ai](https://pub.dev/packages/vision_ai).

Provides camera preview with hand landmark skeleton, face bounding boxes, gesture labels, and emotion indicators -- ready to use in one widget.

## Usage

```dart
import 'package:vision_ai/vision_ai.dart';
import 'package:vision_ai_flutter/vision_ai_flutter.dart';

// In your widget:
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
  showHandLandmarks: true,
  showFaceBoundingBox: true,
  showGestureLabel: true,
  showEmotionLabel: true,
  style: const OverlayStyle(
    handLandmark: LandmarkStyle(
      dotColor: Colors.red,
      lineColor: Colors.green,
    ),
  ),
)
```

## Widgets

| Widget | Description |
|--------|-------------|
| `VisionAiCameraView` | Camera preview + all overlays in one widget |
| `HandLandmarkPainter` | CustomPainter for hand skeleton (dots + lines) |
| `FaceOverlayPainter` | CustomPainter for face bounding box |
| `GestureLabel` | Gesture name overlay |
| `EmotionIndicator` | Emotion name + confidence overlay |
| `ConfidenceBar` | Horizontal confidence progress bar |

## License

MIT
