## 0.2.0 - 2026-05-30

### Features
- **Live camera switching** — `switchCamera()` now flips between the front and back camera in place while running, with no stop/start cycle. The preview keeps rendering (the texture stays valid) and detection continues uninterrupted. Previously this was effectively a no-op that required a manual restart.

### Performance (iOS)
- Hand gesture recognition now uses the GPU (Metal) delegate with automatic CPU fallback, matching Android (was CPU-only).
- Emotion preprocessing reuses per-frame buffers via `PixelBufferPool` and fills the TFLite input buffer in place, removing repeated per-frame allocations in the face pipeline.

### Behavior
- `detectLandmarks` is now consistently a start-time-only option on both platforms: `updateFaceConfig` preserves the value set at `startCamera` rather than changing it (Android could previously reset it at runtime). Toggle it via `startCamera`/restart.

### Fixes & cleanup
- Removed dead `CameraManager.stop()` on Android (`stopCamera` already routes through `release()`).
- Clarified in docs that `minEmotionConfidence` is currently stored but not enforced (no behavior change).

> **iOS note:** the iOS items above ship as part of the ongoing iOS Beta and have not yet been built/profiled on a physical device. See the **iOS Beta** section of the README — device testing is welcome.

## 0.1.1 - 2026-05-25

### Fixes
- Fixed release build crash caused by R8 code shrinking stripping MediaPipe's stack-walking classes — added ProGuard consumer rules
- Fixed `updateFaceConfig` silently resetting `detectLandmarks` to false — now properly preserves the value
- Fixed `onDetachedFromEngine` closing ML processors on the main thread instead of the analysis thread — prevents race condition crashes
- Fixed `EmotionClassifier.loadModelFile()` leaking AssetFileDescriptor and FileInputStream — now uses Kotlin `.use {}` auto-close
- Fixed missing `ON_CREATE` lifecycle event in `PluginLifecycleOwner` — prevents potential crashes on some AndroidX versions
- Fixed missing `import Flutter` in iOS `HandGestureProcessor.swift` and `FaceDetectionProcessor.swift`
- Removed dead code (`pixelBufferToSampleBuffer` always returning nil on iOS)

### Improvements
- Added comprehensive inline comments to all Kotlin, Swift, and Dart source files
- Replaced `setState` with `ValueNotifier` + `ValueListenableBuilder` in example app
- Settings panel now uses grouped cards (Hand Detection, Face Detection, Camera, Overlays)
- Disabling hand/face detection now hides related settings and resets sub-features
- Updated README with detailed API documentation, use cases, and release build instructions
- Added iOS setup instructions (NSCameraUsageDescription)
- Added SVG media files for documentation (hand skeleton, face detection, architecture, feature banner)

## 0.1.0 - 2026-05-24

### Hand Detection
- 8 built-in gestures via MediaPipe Gesture Recognizer (fist, open palm, peace, thumbs up/down, pointing up, I love you)
- 5 custom gestures via finger state pattern matching (ok, counting 1-5)
- User-defined custom gestures with wildcard support
- Per-gesture confidence filtering (allow/deny lists, per-gesture thresholds)
- 21 hand landmarks (normalized + world coordinates in meters)
- Per-finger state tracking (extended/closed)
- Hand bounding box (computed from landmarks)
- Hand motion velocity and direction tracking
- Two-hand interaction detection (pinch, clap, touching)
- World coordinate measurements (pinch distance, hand span in cm)

### Face Detection
- 7 emotion classification (angry, disgusted, fearful, happy, sad, surprised, neutral) via ML Kit + TFLite
- 15 face contour types (full face mesh including cheek centers)
- 10 face landmark points (eyes, nose, mouth, ears, cheeks)
- Face tracking with stable IDs across frames
- Blink detection from eye open probability transitions
- Head nod/shake detection from Euler angle oscillations
- Face distance estimation from bounding box geometry (pinhole camera model)
- Attention scoring (eye openness + face orientation + head stability)
- Accurate detection mode (ML Kit PERFORMANCE_MODE_ACCURATE)

### Performance
- 25-30 FPS real-time processing on mid-range devices
- GPU acceleration with automatic CPU fallback
- Bitmap pooling for reduced GC pressure
- Emission throttling via `CameraConfig.maxResultsPerSecond`
- On-device processing — zero cloud dependencies

### Platform Support
- Android (Kotlin, CameraX, MediaPipe, ML Kit, TFLite)
- iOS (Swift, AVFoundation, MediaPipe, ML Kit, TFLite)

### UI Package (vision_ai_flutter)
- `VisionAiCameraView` composite widget with configurable overlays
- Hand landmark skeleton painter
- Hand bounding box painter
- Face bounding box painter
- Face contour painter (15 types)
- Gesture label and emotion indicator widgets
- Configurable overlay styles (colors, line widths)
