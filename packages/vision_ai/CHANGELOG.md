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
