## 0.1.0

- Initial release (Android only)
- Hand gesture recognition with 13 built-in gestures via MediaPipe Gesture Recognizer
- Custom gesture support with finger state pattern matching
- Facial emotion detection with 7 universal emotions via ML Kit + TFLite
- Combined hand + face detection on a single camera feed at 20-30 FPS
- On-device processing with GPU acceleration and CPU fallback
- Bitmap pooling for reduced GC pressure (~55% fewer GC pauses)
- Emission throttling via `CameraConfig.maxResultsPerSecond` (trade smoothness for CPU savings)
- Face contour detection (133 points across 13 contour types)
- 10 face landmark detection (eye centers, mouth corners, nose, ears, cheeks)
- Blink detection from eye open probability transitions
- Head nod/shake detection from Euler angle oscillations
- Face distance estimation from bounding box geometry
- Configurable overlay widgets via `vision_ai_flutter` (hand skeleton, face box, contours, labels)
- Settings-rich example app with per-feature toggles for testing
