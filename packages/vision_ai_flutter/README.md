# vision_ai_flutter

Pre-built Flutter UI overlay widgets for [vision_ai](https://pub.dev/packages/vision_ai). Camera preview with hand skeleton, face bounding boxes, contour mesh, gesture labels, and emotion indicators — one widget does it all.

[![pub package](https://img.shields.io/pub/v/vision_ai_flutter.svg)](https://pub.dev/packages/vision_ai_flutter)

<p align="center">
  <img src="https://raw.githubusercontent.com/OttomanDeveloper/vision_ai/main/assets/media/hand_skeleton.svg" alt="Hand skeleton" width="45%"/>
  <img src="https://raw.githubusercontent.com/OttomanDeveloper/vision_ai/main/assets/media/face_detection.svg" alt="Face detection" width="45%"/>
</p>

## Installation

```yaml
dependencies:
  vision_ai: ^0.1.0
  vision_ai_flutter: ^0.1.0
```

**Android release builds:** MediaPipe crashes with R8 code shrinking. Add to `android/app/build.gradle.kts`:

```kotlin
android {
    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
```

See the [vision_ai README](https://pub.dev/packages/vision_ai) for full setup (camera permissions, iOS config).

## Quick Start

```dart
import 'package:vision_ai/vision_ai.dart';
import 'package:vision_ai_flutter/vision_ai_flutter.dart';

final vision = VisionAi(hand: HandConfig(), face: FaceConfig());
final textureId = await vision.start();

// One widget handles everything:
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
)
```

That's it — hand skeleton, face box, gesture label, and emotion indicator all render automatically with sensible defaults.

---

## VisionAiCameraView

The main composite widget. Stacks a `Texture` preview with configurable overlay layers, all driven by a single `StreamBuilder` so every layer stays frame-synced.

### All Parameters

```dart
VisionAiCameraView(
  // Required
  controller: vision,             // VisionAi instance
  textureId: textureId,           // from vision.start()
  
  // Toggle overlays (all have sensible defaults)
  showHandLandmarks: true,        // 21-point skeleton with bone connections
  showHandBoundingBox: false,     // yellow rectangle around detected hand
  showFaceBoundingBox: true,      // cyan rectangle around detected face
  showFaceContours: false,        // 15-type face mesh with dots and polylines
  showGestureLabel: true,         // gesture name + confidence at top center
  showEmotionLabel: true,         // emotion name + emoji at bottom center
  
  // Advanced
  mirrorLandmarks: false,         // flip skeleton horizontally (for non-mirrored preview)
  style: const OverlayStyle(),    // colors, sizes, fonts for all overlays
  overlayBuilder: null,           // custom widget on top of everything (gets VisionResult)
)
```

### Overlay Toggle Guide

| Scenario | Recommended toggles |
|---|---|
| Hand gesture app | `showHandLandmarks: true`, `showGestureLabel: true` |
| Emotion detector | `showFaceBoundingBox: true`, `showEmotionLabel: true` |
| Face mesh / AR | `showFaceContours: true`, `showFaceBoundingBox: false` |
| Debug / testing | Everything on |
| Clean camera only | Everything off, use `overlayBuilder` for custom UI |
| Performance-sensitive | `showHandLandmarks: false` (painters cost ~1-2ms per frame) |

### Custom Overlay Builder

For anything beyond the built-in painters, `overlayBuilder` gives you full `VisionResult` access:

```dart
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
  showHandLandmarks: false,  // disable built-in, draw your own
  overlayBuilder: (context, result) {
    if (!result.hasHands) return const SizedBox.shrink();
    final hand = result.primaryHand!;
    
    return Stack(
      children: [
        // Show extended fingers
        Positioned(
          top: 20, left: 20,
          child: Text(
            hand.fingerStates.entries
              .where((e) => e.value == FingerState.extended)
              .map((e) => e.key.name)
              .join(', '),
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
        // Show world-coordinate measurements
        if (hand.worldLandmarks.length >= 21)
          Positioned(
            bottom: 20, left: 20,
            child: Text(
              'Span: ${(hand.worldLandmarks[HandLandmarkIndex.thumbTip].distanceTo(hand.worldLandmarks[HandLandmarkIndex.pinkyTip]) * 100).toStringAsFixed(1)}cm',
              style: const TextStyle(color: Colors.yellow, fontSize: 16),
            ),
          ),
      ],
    );
  },
)
```

The `overlayBuilder` renders on top of all built-in overlays. Return `SizedBox.shrink()` when you have nothing to show.

---

## Painters

Use these `CustomPainter` classes directly if you need custom layout or want to compose your own camera view instead of using `VisionAiCameraView`.

### HandLandmarkPainter

Draws 21 red landmark dots connected by 23 green bone lines.

```dart
CustomPaint(
  painter: HandLandmarkPainter(
    hands: result.hands,        // required
    imageSize: result.imageSize, // required: for coordinate mapping
    style: LandmarkStyle(
      dotColor: Colors.red,     // landmark dot color (default: red)
      lineColor: Colors.green,  // bone connection color (default: green)
      dotRadius: 4.0,           // dot radius in logical pixels
      lineWidth: 2.0,           // line width in logical pixels
    ),
    mirrored: false,            // flip horizontally for non-mirrored previews
  ),
)
```

**Coordinate space:** Landmarks are normalized [0,1]. The painter maps directly to canvas size since Flutter's `Texture` stretches to fill its container.

### HandBoundingBoxPainter

Draws a rectangle computed from the min/max of all 21 landmarks.

```dart
CustomPaint(
  painter: HandBoundingBoxPainter(
    hands: result.hands,
    boxColor: Colors.yellow,    // stroke color (default: yellow)
    boxWidth: 2.0,              // stroke width
    mirrored: false,            // mirrors the box for flipped previews
  ),
)
```

### FaceOverlayPainter

Draws a rectangle around each detected face.

```dart
CustomPaint(
  painter: FaceOverlayPainter(
    faces: result.faces,
    imageSize: result.imageSize,  // required: face bbox is in pixel coords
    boxColor: Colors.cyan,       // stroke color (default: cyan)
    boxWidth: 2.0,               // stroke width
  ),
)
```

**Coordinate space:** Face bounding boxes are in pixel coordinates relative to `imageSize`. The painter scales to canvas size.

### FaceContourPainter

Draws 15 contour polylines with dots for each face. Polylines are open (not closed paths) — ML Kit doesn't guarantee closed contours.

```dart
CustomPaint(
  painter: FaceContourPainter(
    faces: result.faces,
    imageSize: result.imageSize,
    dotColor: Colors.greenAccent,  // contour point color
    lineColor: Colors.greenAccent, // polyline color
    dotRadius: 2.0,
    lineWidth: 1.5,
  ),
)
```

Requires `FaceConfig(detectContours: true)`. Renders: face outline, left/right eyebrow (top + bottom), left/right eye, upper/lower lip (top + bottom), nose bridge, nose bottom, left/right cheek.

---

## Label Widgets

### GestureLabel

Shows the gesture name and confidence on a rounded dark background.

```dart
GestureLabel(
  hand: result.primaryHand!,
  style: LabelStyle(
    textColor: Colors.white,
    backgroundColor: Colors.black87,
    fontSize: 20.0,
    fontWeight: FontWeight.bold,
    borderRadius: 12.0,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
)
```

Returns `SizedBox.shrink()` when `gesture == Gesture.none`.

### EmotionIndicator

Shows the emotion name with an emoji and optional confidence percentage.

```dart
EmotionIndicator(
  face: result.primaryFace!,
  style: LabelStyle(backgroundColor: Colors.blue),
  showConfidence: true,  // "HAPPY 😊 98%" vs just "HAPPY 😊"
)
```

Emoji mapping: happy=😊, sad=😢, angry=😠, surprised=😮, disgusted=🤢, fearful=😨, neutral=😐.

### ConfidenceBar

Horizontal progress bar showing a 0-100% score.

```dart
ConfidenceBar(
  value: face.emotionConfidence,  // [0.0, 1.0]
  color: Colors.green,
  backgroundColor: Colors.grey[800]!,
  height: 8.0,
  width: 120.0,
)
```

---

## Full Styling Reference

### OverlayStyle

Controls all visual properties when using `VisionAiCameraView`:

```dart
OverlayStyle(
  // Hand skeleton
  handLandmark: LandmarkStyle(
    dotColor: Colors.red,
    lineColor: Colors.green,
    dotRadius: 4.0,
    lineWidth: 2.0,
  ),
  
  // Hand bounding box
  handBoundingBoxColor: Colors.yellow,
  handBoundingBoxWidth: 2.0,
  
  // Face bounding box  
  faceBoundingBoxColor: Colors.cyan,
  faceBoundingBoxWidth: 2.0,
  
  // Gesture label
  gestureLabel: LabelStyle(
    textColor: Colors.white,
    backgroundColor: Colors.black87,
    fontSize: 20.0,
    fontWeight: FontWeight.bold,
    borderRadius: 12.0,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  
  // Emotion label
  emotionLabel: LabelStyle(backgroundColor: Colors.blue),
  showEmotionConfidence: true,
)
```

### Theme Ideas

**Minimal white:**
```dart
OverlayStyle(
  handLandmark: LandmarkStyle(dotColor: Colors.white, lineColor: Colors.white70, dotRadius: 3, lineWidth: 1),
  faceBoundingBoxColor: Colors.white54,
)
```

**Neon cyberpunk:**
```dart
OverlayStyle(
  handLandmark: LandmarkStyle(dotColor: Color(0xFFFF00FF), lineColor: Color(0xFF00FFFF), dotRadius: 5, lineWidth: 3),
  faceBoundingBoxColor: Color(0xFFFF00FF),
  handBoundingBoxColor: Color(0xFF00FFFF),
)
```

**Subtle debug:**
```dart
OverlayStyle(
  handLandmark: LandmarkStyle(dotColor: Colors.blue.withOpacity(0.5), lineColor: Colors.blue.withOpacity(0.3)),
  faceBoundingBoxColor: Colors.grey.withOpacity(0.3),
)
```

---

## Example App

The [vision_ai example app](https://github.com/OttomanDeveloper/vision_ai/tree/main/packages/vision_ai/example) is a full working demo of every widget and painter in this package. Run it to see all overlays in action before writing code:

```bash
git clone https://github.com/OttomanDeveloper/vision_ai.git
cd vision_ai/packages/vision_ai/example
flutter run
```

**What you can toggle in the Overlays card:**
- Hand skeleton (21-point landmark connections)
- Hand bounding box (yellow rectangle)
- Face bounding box (cyan rectangle)
- Face contours (15-type green mesh)
- Gesture label (top center)
- Emotion label (bottom center)
- World coordinates (pinch/span in cm)
- Stats overlay (inference time, finger states, attention score, etc.)

Each overlay toggle applies instantly — no restart needed. The settings panel also groups related options into cards so hand overlays disappear when hand detection is off, and face overlays disappear when face detection is off.

The example also shows how to use `VisionAiCameraView` with `ValueNotifier`-driven settings, so you can see how overlay flags flow from your state into the widget without `setState`.

---

## Tips

- **Performance:** If you only need gesture labels (no skeleton), set `showHandLandmarks: false` — saves ~1-2ms per frame of painter work
- **Contours vs landmarks:** Contours give you detailed face mesh (15 types, hundreds of points). Landmarks give you 10 key points. Contours disable face tracking — use landmarks if you need both tracking and facial points
- **Custom overlay:** Use `overlayBuilder` for game logic, AR effects, or any UI that depends on detection results. It runs on every frame inside the `StreamBuilder`
- **Mirror:** Set `mirrorLandmarks: true` only if your `Texture` is NOT already mirrored. The front camera output is mirrored by default on both Android and iOS

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
