# vision_ai

On-device hand gesture recognition and facial emotion detection for Flutter. Runs at 25-30 FPS with zero cloud dependencies.

[![pub package](https://img.shields.io/pub/v/vision_ai.svg)](https://pub.dev/packages/vision_ai)
[![license](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

<p align="center">
  <img src="https://raw.githubusercontent.com/OttomanDeveloper/vision_ai/main/assets/media/feature_banner.svg" alt="vision_ai banner" width="100%"/>
</p>

## What You Can Build

- **Sign language interpreter** — map 13+ gestures to words with custom finger patterns
- **Driver drowsiness alert** — blink detection + attention scoring triggers warnings
- **Touchless kiosk** — hand motion direction controls UI without touching screen
- **Online exam proctoring** — attention score + face tracking + head nod/shake
- **Fitness rep counter** — track hand landmarks in world coordinates (meters)
- **Interactive children's game** — emotion-driven characters + clap/pinch detection
- **Accessibility controller** — custom gestures → app actions, blink-to-click
- **Live stream reactions** — real-time emotion overlay on broadcaster's face
- **AR filter trigger** — face contours + landmarks drive filter positioning
- **Social distance monitor** — face distance estimation in cm

## Platform Support

| Platform | Status | Min Version | Notes |
|---|---|---|---|
| Android | Stable | API 24 (Android 7.0) | Tested on Samsung Galaxy A15 and other devices |
| iOS | Beta | iOS 12.0 | Implementation complete — community testing welcome ([report issues](https://github.com/OttomanDeveloper/vision_ai/issues)) |

## Installation

```yaml
dependencies:
  vision_ai: ^0.1.0
  vision_ai_flutter: ^0.1.0  # optional: pre-built camera overlay widgets
```

### Android

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS

Add camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed for hand gesture and face detection.</string>
```

---

## Core API

### VisionAi

The main controller. Create it, start the camera, listen to results, dispose when done.

```dart
// Hand + face combined
final vision = VisionAi(
  hand: HandConfig(maxHands: 2),
  face: FaceConfig(detectEmotion: true),
  camera: CameraConfig(facing: CameraFacing.front),
);

// Or use factory constructors for single-mode:
final handOnly = VisionAi.hand();
final faceOnly = VisionAi.face();
```

| Method | Returns | Description |
|---|---|---|
| `start()` | `Future<int>` | Starts camera + ML processing. Returns texture ID for Flutter's `Texture` widget. |
| `stop()` | `Future<void>` | Stops processing, releases camera. Can `start()` again after. |
| `dispose()` | `Future<void>` | Releases everything. Instance is unusable after this. |
| `results` | `Stream<VisionResult>` | Per-frame detection results. Active between `start()` and `stop()`. |
| `updateHandConfig(config)` | `Future<void>` | Hot-swap hand settings while running. Requires restart for some changes. |
| `updateFaceConfig(config)` | `Future<void>` | Hot-swap face settings while running. |
| `switchCamera(facing)` | `Future<void>` | Switch front/back. Requires stop+start to take effect. |
| `isRunning` | `bool` | Whether the camera is actively processing frames. |

### VisionResult

Every frame produces one of these. Contains all detected hands and faces for that frame.

```dart
vision.results.listen((result) {
  print('Hands: ${result.hands.length}, Faces: ${result.faces.length}');
  print('Frame size: ${result.imageSize}');
  print('ML took: ${result.inferenceTimeMs}ms');
});
```

| Property | Type | Description |
|---|---|---|
| `hands` | `List<HandResult>` | All detected hands (0, 1, or 2 depending on `maxHands`) |
| `faces` | `List<FaceResult>` | All detected faces |
| `timestampMs` | `int` | Milliseconds since device boot |
| `imageSize` | `Size` | Camera frame dimensions (for scaling overlays) |
| `inferenceTimeMs` | `int` | Combined hand + face ML processing time |
| `primaryHand` | `HandResult?` | Hand with highest gesture confidence, or null |
| `primaryFace` | `FaceResult?` | Face with highest emotion confidence, or null |
| `hasHands` | `bool` | `hands.isNotEmpty` |
| `hasFaces` | `bool` | `faces.isNotEmpty` |

---

## Hand Detection

### HandConfig

```dart
HandConfig(
  maxHands: 2,                    // 1 or 2 hands to detect
  minDetectionConfidence: 0.5,    // [0.0, 1.0] — lower = more detections, more false positives
  minPresenceConfidence: 0.5,     // [0.0, 1.0] — confidence hand is still present between frames
  minTrackingConfidence: 0.5,     // [0.0, 1.0] — landmark tracking quality threshold
  customGestures: [...],          // your own finger patterns (see below)
  allowedGestures: {Gesture.peace, Gesture.thumbsUp},  // only report these (null = all)
  deniedGestures: {Gesture.fist},                       // block these (null = none)
  gestureThresholds: {Gesture.thumbsUp: 0.8},           // per-gesture min confidence
)
```

### HandResult

Each detected hand has landmarks, gesture, finger states, and a bounding box.

```dart
final hand = result.primaryHand;
if (hand != null) {
  print(hand.gesture);            // Gesture.peace
  print(hand.gestureConfidence);  // 0.95
  print(hand.isLeftHand);         // true/false (from camera's perspective)
  print(hand.customGestureName);  // "rock" (only for user-defined gestures)
  print(hand.boundingBox);        // Rect in normalized [0,1] coords
}
```

| Property | Type | Description |
|---|---|---|
| `gesture` | `Gesture` | Detected gesture enum (fist, peace, thumbsUp, etc.) |
| `gestureConfidence` | `double` | [0.0, 1.0] confidence for the gesture |
| `customGestureName` | `String?` | Non-null only for user-defined custom gestures |
| `landmarks` | `List<NormalizedLandmark>` | 21 points in [0.0, 1.0] image coordinates |
| `worldLandmarks` | `List<WorldLandmark>` | 21 points in meters (real-world scale) |
| `isLeftHand` | `bool` | Handedness from camera's perspective |
| `handednessConfidence` | `double` | How confident the L/R classification is |
| `fingerStates` | `Map<Finger, FingerState>` | Extended/closed for each finger |
| `boundingBox` | `Rect?` | Normalized bounding box from landmark min/max. Null if no landmarks. |

### Finger States

Check which fingers are extended:

```dart
final fingers = hand.fingerStates;
if (fingers[Finger.indexFinger] == FingerState.extended &&
    fingers[Finger.middle] == FingerState.extended) {
  print('Peace sign!');
}

// Count extended fingers
final count = fingers.values.where((s) => s == FingerState.extended).length;
print('$count fingers up');
```

### 21 Hand Landmarks

Each hand has 21 3D landmarks. Use `HandLandmarkIndex` constants to access specific joints:

```dart
final wrist = hand.landmarks[HandLandmarkIndex.wrist];         // index 0
final thumbTip = hand.landmarks[HandLandmarkIndex.thumbTip];   // index 4
final indexTip = hand.landmarks[HandLandmarkIndex.indexTip];   // index 8
final middleTip = hand.landmarks[HandLandmarkIndex.middleTip]; // index 12
final pinkyTip = hand.landmarks[HandLandmarkIndex.pinkyTip];   // index 20

// Convert to pixel coordinates for drawing
final pixelPos = wrist.toOffset(screenWidth, screenHeight);

// All 23 bone connections for skeleton rendering:
for (final bone in HandLandmarkIndex.connections) {
  final from = hand.landmarks[bone[0]];
  final to = hand.landmarks[bone[1]];
  // draw line from → to
}
```

**Landmark indices:** 0=wrist, 1-4=thumb (CMC→tip), 5-8=index (MCP→tip), 9-12=middle, 13-16=ring, 17-20=pinky.

### World Coordinates (Meters)

`worldLandmarks` give real-world 3D positions relative to the hand's center. Use them to measure actual distances:

```dart
// Pinch distance in centimeters
final thumbTip = hand.worldLandmarks[HandLandmarkIndex.thumbTip];
final indexTip = hand.worldLandmarks[HandLandmarkIndex.indexTip];
final pinchCm = thumbTip.distanceTo(indexTip) * 100;
print('Pinch gap: ${pinchCm.toStringAsFixed(1)}cm');

// Hand span (thumb to pinky)
final pinkyTip = hand.worldLandmarks[HandLandmarkIndex.pinkyTip];
final spanCm = thumbTip.distanceTo(pinkyTip) * 100;
print('Hand span: ${spanCm.toStringAsFixed(1)}cm');
```

### Custom Gestures

Define finger patterns. Fingers not in the map act as wildcards (any state matches):

```dart
HandConfig(
  customGestures: [
    // Rock sign: index + pinky up, others down
    CustomGesture(
      name: 'rock',
      fingerStates: {
        Finger.thumb: FingerState.closed,
        Finger.indexFinger: FingerState.extended,
        Finger.middle: FingerState.closed,
        Finger.ring: FingerState.closed,
        Finger.pinky: FingerState.extended,
      },
    ),
    // Gun: thumb + index up (other fingers are wildcards)
    CustomGesture(
      name: 'gun',
      fingerStates: {
        Finger.thumb: FingerState.extended,
        Finger.indexFinger: FingerState.extended,
      },
    ),
  ],
)
```

Custom gestures are checked after built-in MediaPipe gestures fail. Priority: OK → counting 1-5 → your patterns (first match wins).

When a custom gesture matches, `hand.gesture == Gesture.custom` and `hand.customGestureName == "rock"`.

### Gesture Filtering

Control which gestures are reported:

```dart
HandConfig(
  // Only report these (everything else becomes Gesture.none)
  allowedGestures: {Gesture.thumbsUp, Gesture.peace, Gesture.fist},
  
  // OR block specific ones (everything else passes through)
  deniedGestures: {Gesture.fist, Gesture.openHand},
  
  // Raise the bar for specific gestures
  gestureThresholds: {
    Gesture.thumbsUp: 0.8,  // must be 80%+ confident
    Gesture.peace: 0.7,
  },
)
```

Filtering happens after MediaPipe classification but before custom gesture fallback. So if `fist` is denied and the user makes a fist, the custom gesture classifier still gets a chance.

### Supported Gestures

| Gesture | Enum | Source | When detected |
|---|---|---|---|
| Fist | `Gesture.fist` | MediaPipe | All fingers closed |
| Open Hand | `Gesture.openHand` | MediaPipe | All fingers spread |
| Peace | `Gesture.peace` | MediaPipe | Index + middle up |
| Thumbs Up | `Gesture.thumbsUp` | MediaPipe | Thumb up, others closed |
| Thumbs Down | `Gesture.thumbsDown` | MediaPipe | Thumb down, others closed |
| Pointing Up | `Gesture.pointingUp` | MediaPipe | Index up, others closed |
| I Love You | `Gesture.iLoveYou` | MediaPipe | Thumb + index + pinky |
| OK | `Gesture.ok` | Custom | Thumb-index pinch, others extended |
| One–Five | `Gesture.one`–`Gesture.five` | Custom | Counting patterns |
| User-defined | `Gesture.custom` | Your config | Check `customGestureName` |

---

## Face Detection

### FaceConfig

```dart
FaceConfig(
  detectEmotion: true,       // run TFLite emotion classifier (~5-15ms extra)
  detectLandmarks: false,    // 10 face landmark points (eyes, nose, mouth, ears, cheeks)
  detectContours: false,     // 15 face contour types (detailed mesh)
  minFaceSize: 0.1,          // [0.0, 1.0] — fraction of image width; smaller = slower
  enableTracking: true,      // stable face IDs across frames (can't use with contours)
  minEmotionConfidence: 0.4, // stored for future filtering
  accurateMode: false,       // ML Kit ACCURATE mode — better for distant faces, ~2-3x slower
)
```

**Note:** Contour mode and face tracking are mutually exclusive (ML Kit limitation on both platforms). Enabling contours automatically disables tracking.

### FaceResult

```dart
final face = result.primaryFace;
if (face != null) {
  print(face.emotion);              // Emotion.happy
  print(face.emotionConfidence);    // 0.98
  print(face.smilingProbability);   // 0.95 (null if not available)
  print(face.leftEyeOpenProbability);  // 0.92
  print(face.rightEyeOpenProbability); // 0.88
  print(face.trackingId);           // 42 (-1 when tracking disabled)
  print(face.boundingBox);          // Rect in pixel coordinates
  
  // Euler angles (degrees)
  print(face.headEulerAngleX);  // pitch: positive = looking up
  print(face.headEulerAngleY);  // yaw: positive = turned right  
  print(face.headEulerAngleZ);  // roll: positive = head tilted right
  
  // Emotion scores for all 7 classes
  face.emotionScores.forEach((emotion, score) {
    print('$emotion: ${(score * 100).toStringAsFixed(0)}%');
  });
}
```

| Property | Type | Description |
|---|---|---|
| `emotion` | `Emotion` | Highest-scoring emotion |
| `emotionConfidence` | `double` | [0.0, 1.0] score for the top emotion |
| `emotionScores` | `Map<Emotion, double>` | All 7 class probabilities |
| `boundingBox` | `Rect` | Face position in pixel coordinates |
| `headEulerAngleX` | `double` | Pitch in degrees (+ = looking up) |
| `headEulerAngleY` | `double` | Yaw in degrees (+ = turned right) |
| `headEulerAngleZ` | `double` | Roll in degrees (+ = tilted right) |
| `smilingProbability` | `double?` | [0.0, 1.0] or null |
| `leftEyeOpenProbability` | `double?` | [0.0, 1.0] or null |
| `rightEyeOpenProbability` | `double?` | [0.0, 1.0] or null |
| `trackingId` | `int` | Stable ID across frames (-1 when tracking off) |
| `landmarks` | `List<Offset>?` | 10 points in pixel coords (null when `detectLandmarks: false`) |
| `contours` | `List<List<Offset>>?` | 15 contour polylines (null when `detectContours: false`) |

### Supported Emotions

| Emotion | Enum | Reliability | Notes |
|---|---|---|---|
| Happy | `Emotion.happy` | High | Smiles detected very reliably |
| Neutral | `Emotion.neutral` | High | Default resting face |
| Surprised | `Emotion.surprised` | High | Wide eyes + open mouth |
| Sad | `Emotion.sad` | Medium | Works with exaggerated expressions |
| Angry | `Emotion.angry` | Medium | Furrowed brows help |
| Disgusted | `Emotion.disgusted` | Low | Often confused with angry |
| Fearful | `Emotion.fearful` | Low | Often confused with surprised |

### Face Landmarks (10 points)

When `detectLandmarks: true`, pixel-coordinate positions for:

| Index | Point | Use case |
|---|---|---|
| 0 | Left eye center | Gaze direction, blink |
| 1 | Right eye center | Gaze direction, blink |
| 2 | Nose base | Face center reference |
| 3 | Mouth left corner | Smile detection |
| 4 | Mouth right corner | Smile width |
| 5 | Mouth bottom | Mouth open detection |
| 6 | Left ear | Face width |
| 7 | Right ear | Face width |
| 8 | Left cheek | Face shape |
| 9 | Right cheek | Face shape |

Missing points (face turned away) return `Offset(-1, -1)`.

### Face Contours (15 types)

When `detectContours: true`, detailed polylines for face mesh rendering:

Face outline, left/right eyebrow (top + bottom), left/right eye, upper/lower lip (top + bottom), nose bridge, nose bottom, left/right cheek center.

Each contour is a `List<Offset>` of connected points in pixel coordinates.

---

## Dart-Only Detectors

These run entirely in Dart — no native code, no extra ML models. They consume `FaceResult` or `HandResult` from the stream and compute higher-level events. All are stateful: create once, feed every frame, call `reset()` when switching subjects.

### BlinkDetector

Detects eye blinks from open/close probability transitions.

```dart
final blinkDetector = BlinkDetector(
  openThreshold: 0.7,       // above this = "eyes open"
  closedThreshold: 0.3,     // below this = "eyes closed"
  maxBlinkDurationMs: 500,  // longer closures are ignored (not a blink)
);

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final blink = blinkDetector.update(face, result.timestampMs);
    if (blink != null) {
      print('${blink.eye} blink, ${blink.durationMs}ms'); // BlinkEye.left, .right, or .both
    }
  }
});
```

**Use cases:** Blink-to-click for accessibility, drowsiness detection (slow/frequent blinks), liveness check for authentication.

### HeadGestureDetector

Detects head nod (yes) and shake (no) from Euler angle oscillations.

```dart
final headDetector = HeadGestureDetector(
  nodAngleThreshold: 8.0,      // degrees of pitch change to count as a nod movement
  shakeAngleThreshold: 10.0,   // degrees of yaw change to count as a shake movement
  minOscillations: 3,          // direction changes needed (3 = 1.5 back-and-forth cycles)
  windowMs: 1000,              // oscillations must happen within this time window
  cooldownMs: 1500,            // wait after detection before allowing another
);

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final gesture = headDetector.update(face, result.timestampMs);
    if (gesture != null) {
      print(gesture.gesture == HeadGesture.nod ? 'YES' : 'NO');
    }
  }
});
```

**Use cases:** Hands-free yes/no input, survey responses, accessibility confirmation.

### FaceDistanceEstimator

Estimates camera-to-face distance using the pinhole camera model.

```dart
final distanceEstimator = FaceDistanceEstimator(
  assumedFaceWidthCm: 15.0,  // average adult face ~14-16cm
  cameraFovDegrees: 75.0,    // most phone front cameras are 70-80 degrees
);

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final estimate = distanceEstimator.estimate(face, result.imageSize);
    if (estimate != null) {
      print('${estimate.distanceCm.toStringAsFixed(0)}cm — ${estimate.zone.name}');
      // Zones: veryClose (<30cm), close (30-60cm), medium (60-120cm), far (>120cm)
    }
  }
});
```

**Use cases:** Screen distance warnings, social distancing, zoom-based UI scaling. Accuracy is ~20-30%, good for zone detection, not precise measurement.

### AttentionScorer

Combines three signals into a single 0-100% attention/engagement score:

- **Eye openness** (40% weight) — average of both eyes
- **Face orientation** (40% weight) — pitch + yaw distance from center
- **Head stability** (20% weight) — inverse of angular velocity over 500ms

```dart
final scorer = AttentionScorer(
  eyeWeight: 0.4,
  orientationWeight: 0.4,
  stabilityWeight: 0.2,
  maxPitchDegrees: 45.0,       // beyond this angle, orientation score = 0
  maxYawDegrees: 45.0,
  stabilityWindowMs: 500,
  maxAngularVelocity: 60.0,    // degrees/sec above which stability = 0
);

vision.results.listen((result) {
  final face = result.primaryFace;
  if (face != null) {
    final attention = scorer.update(face, result.timestampMs);
    if (attention != null) {
      print('Attention: ${(attention.score * 100).toStringAsFixed(0)}% (${attention.level.name})');
      print('  Eye: ${(attention.eyeScore * 100).toStringAsFixed(0)}%');
      print('  Orientation: ${(attention.orientationScore * 100).toStringAsFixed(0)}%');
      print('  Stability: ${(attention.stabilityScore * 100).toStringAsFixed(0)}%');
      // AttentionLevel: high (>=75%), medium (45-75%), low (15-45%), none (<15%)
    }
  }
});
```

**Use cases:** E-learning engagement tracking, proctoring, driver monitoring, meeting participation.

### HandMotionTracker

Tracks hand velocity and movement direction across frames.

```dart
final tracker = HandMotionTracker(
  windowMs: 200,                // velocity averaged over this window
  stillThreshold: 0.02,         // below this speed = still
  trackingLandmarkIndex: 0,     // 0 = wrist (default), or any landmark index
);

vision.results.listen((result) {
  final hand = result.primaryHand;
  if (hand != null) {
    final motion = tracker.update(hand, result.timestampMs);
    if (motion != null) {
      print('Speed: ${motion.speed.toStringAsFixed(2)}/s');  // normalized units/sec
      print('Direction: ${motion.direction.name}');          // up, upRight, right, etc.
      print('State: ${motion.state.name}');                  // still, slow, moderate, fast
      print('Velocity: (${motion.velocityX}, ${motion.velocityY})');
    }
  }
});
```

**Directions:** `up`, `upRight`, `right`, `downRight`, `down`, `downLeft`, `left`, `upLeft` (8 compass points).

**States:** `still` (<0.02), `slow` (0.02-0.15), `moderate` (0.15-0.5), `fast` (>0.5 normalized units/sec).

**Use cases:** Swipe gesture recognition, wave detection, touchless scrolling direction.

### TwoHandInteractionDetector

Detects interactions between two hands.

```dart
final twoHand = TwoHandInteractionDetector(
  pinchThreshold: 0.06,          // index tips within 6% of image width
  touchThreshold: 0.08,          // any fingertips within 8%
  clapVelocityThreshold: 0.3,    // wrist approach speed for clap
  cooldownMs: 500,               // ms between detections
);

vision.results.listen((result) {
  final event = twoHand.update(result);  // takes full VisionResult, not single hand
  if (event != null) {
    print('${event.gesture.name} at distance ${event.distance.toStringAsFixed(3)}');
    // TwoHandGesture: pinch, clap, touching
  }
});
```

Requires `HandConfig(maxHands: 2)`. Detection priority: pinch (most specific) → clap (velocity-based) → touching (fallback).

**Use cases:** Zoom gestures, clap-to-action, collaborative interactions.

---

## Camera Configuration

```dart
CameraConfig(
  facing: CameraFacing.front,           // .front or .back
  resolution: AnalysisResolution.medium, // .low (320x240), .medium (640x480), .high (1280x720)
  maxResultsPerSecond: 0,               // 0 = no throttle (every frame)
)
```

### Emission Throttling

Control how many results per second reach Dart. The ML pipeline still runs at full speed — throttling only skips the emission so the next result is always fresh.

| Value | Effect | Best for |
|---|---|---|
| `0` | Every frame (~20-30 FPS) | Smooth hand skeleton drawing |
| `10-15` | Balanced | Gesture/emotion labels with acceptable landmark lag |
| `5` | Labels only | Minimal CPU, choppy skeletons |

```dart
CameraConfig(maxResultsPerSecond: 10)
```

---

## Camera Preview

`VisionAi.start()` returns a texture ID. Render with Flutter's `Texture` widget:

```dart
final textureId = await vision.start();
// In your build:
Texture(textureId: textureId)
```

Or use [`VisionAiCameraView`](https://pub.dev/packages/vision_ai_flutter) from `vision_ai_flutter` for a complete solution with overlays.

---

## Architecture

All ML inference runs on-device:

- **Hand gestures**: MediaPipe Gesture Recognizer (~8MB model, GPU delegate with CPU fallback)
- **Face detection**: Google ML Kit Face Detection (bundled per-platform)
- **Emotion**: TFLite CNN trained on FER2013 (~2MB model, 2 inference threads)

Camera frames are processed natively (CameraX on Android, AVFoundation on iOS). Only lightweight results cross the platform channel — raw frame data never leaves the native side.

## Example App

The package ships with a full-featured demo app that lets you test every feature before writing any code. It includes a settings panel with per-feature toggles organized into cards, so you can enable/disable individual capabilities and see the results in real-time.

```bash
cd example
flutter run
```

**What you can test:**
- Toggle hand detection, face detection, or both simultaneously
- Switch between front/back camera and low/medium/high resolution
- Enable hand motion tracking, two-hand interaction, gesture filtering
- Enable blink detection, head nod/shake, face distance, attention scoring
- Toggle individual overlays: hand skeleton, hand bounding box, face box, face contours, gesture label, emotion label, world coordinates
- Adjust detection confidence, min face size, max results/sec with sliders
- Try accurate mode for face detection
- Define a custom "rock" gesture out of the box

All toggles apply instantly for overlay settings. Detection and camera changes require a restart (tap Stop then Start). When you disable hand or face detection, all related sub-settings and overlay options disappear automatically and reset to defaults.

The example also serves as a reference implementation showing how to use `ValueNotifier` + `ValueListenableBuilder` instead of `setState` for reactive state management with this package.

## iOS Beta

The iOS implementation is complete and mirrors the Android architecture (AVFoundation + MediaPipe + ML Kit + TFLite), but has not been extensively tested on physical devices. If you have a Mac + iPhone/iPad:

1. Run the example app: `cd example && flutter run`
2. Test hand gestures, face detection, emotion classification
3. Share crash logs or issues at [GitHub Issues](https://github.com/OttomanDeveloper/vision_ai/issues) with the `ios` label

Your testing helps us move iOS from Beta to Stable.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Forks must retain attribution and state changes.
