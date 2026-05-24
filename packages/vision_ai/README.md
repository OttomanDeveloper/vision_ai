# vision_ai

On-device hand gesture recognition and facial emotion detection for Flutter. Runs at 25+ FPS with zero cloud dependencies.

## Features

- **Hand Gesture Recognition** — 13 built-in gestures + unlimited custom gestures
- **Facial Emotion Detection** — 7 universal emotions with confidence scores
- **Face Contours** — 133-point face mesh (outline, eyes, lips, eyebrows, nose)
- **Face Landmarks** — 10-point lightweight detection (works with tracking)
- **Blink Detection** — detects eye blinks from open/close transitions
- **Head Nod/Shake** — detects yes/no head gestures from Euler angle oscillations
- **Face Distance** — estimates camera-to-face distance from bounding box geometry
- **Emission Throttling** — configurable results/sec to balance smoothness vs CPU
- **Bitmap Pooling** — reuses allocations to minimize GC pauses
- **Real-time** — 20-30 FPS on modern Android devices
- **On-device** — No server, no API keys, no internet required
- **Combined** — Run hand + face detection simultaneously on the same camera feed

## Supported Gestures

| Gesture | Enum | Source |
|---------|------|--------|
| Fist | `Gesture.fist` | MediaPipe |
| Open Hand | `Gesture.openHand` | MediaPipe |
| Peace / Victory | `Gesture.peace` | MediaPipe |
| Thumbs Up | `Gesture.thumbsUp` | MediaPipe |
| Thumbs Down | `Gesture.thumbsDown` | MediaPipe |
| Pointing Up | `Gesture.pointingUp` | MediaPipe |
| I Love You | `Gesture.iLoveYou` | MediaPipe |
| OK | `Gesture.ok` | Custom classifier |
| One through Five | `Gesture.one` - `Gesture.five` | Custom classifier |
| User-defined | `Gesture.custom` | Your pattern |

## Supported Emotions

| Emotion | Enum | Reliability |
|---------|------|-------------|
| Happy | `Emotion.happy` | High |
| Sad | `Emotion.sad` | Medium |
| Angry | `Emotion.angry` | Medium |
| Surprised | `Emotion.surprised` | High |
| Disgusted | `Emotion.disgusted` | Low |
| Fearful | `Emotion.fearful` | Low |
| Neutral | `Emotion.neutral` | High |

## Installation

```yaml
dependencies:
  vision_ai: ^0.1.0
  vision_ai_flutter: ^0.1.0  # Optional: pre-built UI overlay widgets
```

### Android Setup

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

Minimum SDK: 24 (Android 7.0)

## Quick Start

### Hand gestures only

```dart
final vision = VisionAi.hand();
final textureId = await vision.start();

vision.results.listen((result) {
  final hand = result.primaryHand;
  if (hand != null) {
    print('${hand.gesture} (${hand.gestureConfidence})');
  }
});
```

### Face emotions only

```dart
final vision = VisionAi.face();
final textureId = await vision.start();

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    print('${face.emotion} (${face.emotionConfidence})');
  }
});
```

### Combined (hand + face)

```dart
final vision = VisionAi(
  hand: HandConfig(maxHands: 2),
  face: FaceConfig(detectEmotion: true),
);
final textureId = await vision.start();

vision.results.listen((result) {
  print('Hands: ${result.hands.length}, Faces: ${result.faces.length}');
});
```

### Custom gestures

```dart
final vision = VisionAi.hand(
  config: HandConfig(
    customGestures: [
      CustomGesture(
        name: 'rock',
        fingerStates: {
          Finger.indexFinger: FingerState.extended,
          Finger.pinky: FingerState.extended,
          Finger.thumb: FingerState.closed,
          Finger.middle: FingerState.closed,
          Finger.ring: FingerState.closed,
        },
      ),
    ],
  ),
);
```

### With UI overlays (vision_ai_flutter)

```dart
VisionAiCameraView(
  controller: vision,
  textureId: textureId,
  showHandLandmarks: true,    // Red dots + green lines
  showFaceBoundingBox: true,   // Cyan rectangle
  showFaceContours: true,      // 133-point face mesh
  showGestureLabel: true,      // Gesture name overlay
  showEmotionLabel: true,      // Emotion name overlay
)
```

### Blink detection

```dart
final blinkDetector = BlinkDetector();

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final blink = blinkDetector.update(face, result.timestampMs);
    if (blink != null) {
      print('Blinked: ${blink.eye}'); // left, right, or both
    }
  }
});
```

### Head nod/shake detection

```dart
final headDetector = HeadGestureDetector();

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final gesture = headDetector.update(face, result.timestampMs);
    if (gesture != null) {
      print(gesture.gesture == HeadGesture.nod ? 'Yes!' : 'No!');
    }
  }
});
```

### Face distance estimation

```dart
final distanceEstimator = FaceDistanceEstimator();

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final estimate = distanceEstimator.estimate(face, result.imageSize);
    if (estimate != null) {
      print('${estimate.distanceCm}cm (${estimate.zone.name})');
    }
  }
});
```

### Emission throttling

```dart
// Limit to 10 results/sec to reduce main thread work.
// Set 0 for no limit (smoothest landmark tracking).
final vision = VisionAi(
  hand: HandConfig(),
  camera: CameraConfig(maxResultsPerSecond: 10),
);
```

## Camera Preview

`VisionAi.start()` returns a texture ID. Render it with Flutter's `Texture` widget:

```dart
Texture(textureId: textureId)
```

Or use `VisionAiCameraView` from `vision_ai_flutter` for a complete solution with overlays.

## Platform Support

| Platform | Status |
|----------|--------|
| Android | Supported (API 24+) |
| iOS | Planned (v1.1) |
| Web | Planned (v1.2) |

## Architecture

All ML inference runs on the device GPU/NPU:

- **Hand gestures**: MediaPipe Gesture Recognizer (~8MB model)
- **Face detection**: Google ML Kit Face Detection
- **Emotion classification**: TFLite CNN on FER2013 (~2MB model)

Camera frames are processed natively via CameraX. Only lightweight results (landmarks, labels, scores) cross the platform channel -- frame data never leaves the native side.

## License

Apache 2.0 -- see [LICENSE](LICENSE) and [NOTICE](NOTICE). Forks must retain attribution and state changes.
