# vision_ai

On-device hand gesture recognition and facial emotion detection for Flutter. Runs at 25-30 FPS with zero cloud dependencies.

[![pub package](https://img.shields.io/pub/v/vision_ai.svg)](https://pub.dev/packages/vision_ai)
[![license](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

<p align="center">
  <img src="https://raw.githubusercontent.com/OttomanDeveloper/vision_ai/main/assets/media/feature_banner.svg" alt="vision_ai banner" width="100%"/>
</p>

## Features

### Hand Detection
- **13 built-in gestures** — fist, open palm, peace, thumbs up/down, pointing up, I love you, ok, counting 1-5
- **Custom gestures** — define your own with finger state patterns and wildcards
- **21 hand landmarks** — normalized image coords + world coordinates in meters
- **Per-finger tracking** — extended/closed state for all 5 fingers
- **Hand bounding box** — computed from landmark min/max
- **Motion tracking** — velocity, direction (8 compass points), speed categories
- **Two-hand interaction** — detect pinch, clap, and hands touching
- **Gesture filtering** — allow/deny lists and per-gesture confidence thresholds
- **World measurements** — real distances in cm (pinch gap, hand span)

### Face Detection
- **7 emotion classes** — happy, sad, angry, surprised, disgusted, fearful, neutral
- **15 face contour types** — full face mesh (outline, eyes, lips, eyebrows, nose, cheeks)
- **10 landmark points** — eyes, nose, mouth, ears, cheeks
- **Face tracking** — stable IDs across frames
- **Blink detection** — per-eye with duration tracking
- **Head nod/shake** — yes/no gesture detection from Euler angles
- **Distance estimation** — camera-to-face distance via pinhole model
- **Attention scoring** — combines eye openness, orientation, and head stability
- **Accurate mode** — ML Kit's high-quality detection for distant/angled faces

### Performance
- **25-30 FPS** on mid-range devices
- **GPU acceleration** with automatic CPU fallback
- **Buffer pooling** — reuses allocations to minimize GC pressure
- **Emission throttling** — configurable results/sec via `CameraConfig.maxResultsPerSecond`
- **100% on-device** — no server, no API keys, no internet

## Platform Support

| Platform | Status | Min Version |
|----------|--------|-------------|
| Android  | Supported | API 24 (Android 7.0) |
| iOS      | Supported | iOS 12.0 |

## Installation

```yaml
dependencies:
  vision_ai: ^0.1.0
  vision_ai_flutter: ^0.1.0  # Optional: pre-built overlay widgets
```

### Android Setup

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS Setup

Add camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed for hand gesture and face detection.</string>
```

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
  showHandLandmarks: true,
  showHandBoundingBox: true,
  showFaceBoundingBox: true,
  showFaceContours: true,
  showGestureLabel: true,
  showEmotionLabel: true,
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
      print('Blinked: ${blink.eye} (${blink.durationMs}ms)');
    }
  }
});
```

### Attention scoring

```dart
final scorer = AttentionScorer();

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final attention = scorer.update(face, result.timestampMs);
    if (attention != null) {
      print('Attention: ${attention.score} (${attention.level.name})');
    }
  }
});
```

### Hand motion tracking

```dart
final tracker = HandMotionTracker();

vision.results.listen((result) {
  final hand = result.primaryHand;
  if (hand != null) {
    final motion = tracker.update(hand, result.timestampMs);
    if (motion != null) {
      print('${motion.speed}/s ${motion.direction.name} (${motion.state.name})');
    }
  }
});
```

### World coordinate measurements

```dart
vision.results.listen((result) {
  final hand = result.primaryHand;
  if (hand != null && hand.worldLandmarks.length >= 21) {
    final pinch = hand.worldLandmarks[HandLandmarkIndex.thumbTip]
        .distanceTo(hand.worldLandmarks[HandLandmarkIndex.indexTip]);
    print('Pinch gap: ${(pinch * 100).toStringAsFixed(1)}cm');
  }
});
```

### Gesture filtering

```dart
final vision = VisionAi.hand(
  config: HandConfig(
    deniedGestures: {Gesture.fist, Gesture.openHand},
    gestureThresholds: {Gesture.thumbsUp: 0.8, Gesture.peace: 0.7},
  ),
);
```

### Emission throttling

```dart
final vision = VisionAi(
  hand: HandConfig(),
  camera: CameraConfig(maxResultsPerSecond: 10),
);
```

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

## Architecture

All ML inference runs on-device:

- **Hand gestures**: MediaPipe Gesture Recognizer (~8MB model, GPU delegate)
- **Face detection**: Google ML Kit Face Detection
- **Emotion classification**: TFLite CNN on FER2013 (~2MB model)

Camera frames are processed natively (CameraX on Android, AVFoundation on iOS). Only lightweight results (landmarks, labels, scores) cross the platform channel -- frame data never leaves the native side.

## Camera Preview

`VisionAi.start()` returns a texture ID. Render with Flutter's `Texture` widget:

```dart
Texture(textureId: textureId)
```

Or use `VisionAiCameraView` from `vision_ai_flutter` for overlays.

## License

Apache 2.0 -- see [LICENSE](LICENSE) and [NOTICE](NOTICE). Forks must retain attribution and state changes.
