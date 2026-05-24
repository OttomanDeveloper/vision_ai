# vision_ai_flutter

Pre-built Flutter UI overlay widgets for [vision_ai](https://pub.dev/packages/vision_ai). Camera preview with hand skeleton, face bounding boxes, contour mesh, gesture labels, and emotion indicators — ready to use in one widget.

[![pub package](https://img.shields.io/pub/v/vision_ai_flutter.svg)](https://pub.dev/packages/vision_ai_flutter)

## Installation

```yaml
dependencies:
  vision_ai: ^0.1.0
  vision_ai_flutter: ^0.1.0
```

## Quick Start

```dart
import 'package:vision_ai/vision_ai.dart';
import 'package:vision_ai_flutter/vision_ai_flutter.dart';

final vision = VisionAi(hand: HandConfig(), face: FaceConfig());
final textureId = await vision.start();

// One widget does everything:
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
  showHandLandmarks: true,     // green skeleton + red dots
  showHandBoundingBox: true,   // yellow rectangle around hand
  showFaceBoundingBox: true,   // cyan rectangle around face
  showFaceContours: true,      // green face mesh with dots
  showGestureLabel: true,      // "PEACE 95%" at top
  showEmotionLabel: true,      // "HAPPY 😊 98%" at bottom
)
```

## Widgets

### VisionAiCameraView

The main composite widget. Stacks a `Texture` preview with configurable overlays driven by a single `StreamBuilder` so all layers stay in sync.

```dart
VisionAiCameraView(
  controller: vision,           // required: VisionAi instance
  textureId: textureId,         // required: from vision.start()
  showHandLandmarks: true,      // 21-point skeleton (default: true)
  showHandBoundingBox: false,   // rectangle from landmark min/max (default: false)
  showFaceBoundingBox: true,    // cyan box around face (default: true)
  showFaceContours: false,      // 15-type face mesh (default: false)
  showGestureLabel: true,       // gesture name at top center (default: true)
  showEmotionLabel: true,       // emotion name at bottom center (default: true)
  mirrorLandmarks: false,       // flip skeleton for non-mirrored previews
  style: const OverlayStyle(),  // colors, sizes, fonts
  overlayBuilder: (context, result) {
    // Custom overlay on top of everything — full VisionResult access
    return Text('Hands: ${result.hands.length}');
  },
)
```

### Painters (CustomPainter)

Use these directly if you need custom layout instead of `VisionAiCameraView`:

| Painter | Coordinates | What it draws |
|---|---|---|
| `HandLandmarkPainter` | Normalized [0,1] | 21 red dots + 23 green bone connections |
| `HandBoundingBoxPainter` | Normalized [0,1] | Yellow rectangle from landmark bounds |
| `FaceOverlayPainter` | Pixel coords | Cyan rectangle around face |
| `FaceContourPainter` | Pixel coords | Green polylines + dots for 15 contour regions |

```dart
// Example: hand skeleton only, custom colors
CustomPaint(
  painter: HandLandmarkPainter(
    hands: result.hands,
    imageSize: result.imageSize,
    style: LandmarkStyle(
      dotColor: Colors.blue,
      lineColor: Colors.white,
      dotRadius: 6.0,
      lineWidth: 3.0,
    ),
    mirrored: false,
  ),
)
```

### Label Widgets

| Widget | Shows |
|---|---|
| `GestureLabel` | Gesture name with confidence on dark background |
| `EmotionIndicator` | Emotion name with emoji and optional confidence % |
| `ConfidenceBar` | Horizontal bar 0-100% with percentage text |

## Styling

All visual properties are configurable through `OverlayStyle`:

```dart
VisionAiCameraView(
  style: OverlayStyle(
    handLandmark: LandmarkStyle(
      dotColor: Colors.red,       // landmark dot color
      lineColor: Colors.green,    // bone connection color
      dotRadius: 4.0,             // dot size in logical pixels
      lineWidth: 2.0,             // line width
    ),
    handBoundingBoxColor: Colors.yellow,
    handBoundingBoxWidth: 2.0,
    faceBoundingBoxColor: Colors.cyan,
    faceBoundingBoxWidth: 2.0,
    gestureLabel: LabelStyle(
      textColor: Colors.white,
      backgroundColor: Colors.black87,
      fontSize: 20.0,
      fontWeight: FontWeight.bold,
      borderRadius: 12.0,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    emotionLabel: LabelStyle(backgroundColor: Colors.blue),
    showEmotionConfidence: true,  // show "98%" next to emotion name
  ),
)
```

## Custom Overlays

For anything beyond the built-in painters, use `overlayBuilder`:

```dart
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
  overlayBuilder: (context, result) {
    final hand = result.primaryHand;
    if (hand == null) return const SizedBox.shrink();
    
    return Positioned(
      top: 50,
      left: 20,
      child: Text(
        'Fingers: ${hand.fingerStates.entries
          .where((e) => e.value == FingerState.extended)
          .map((e) => e.key.name)
          .join(", ")}',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  },
)
```

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
