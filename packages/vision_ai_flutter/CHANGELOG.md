## 0.2.0 - 2026-05-30

- Bumped to require `vision_ai` ^0.2.0 (live `switchCamera`, iOS performance improvements). No widget API or behavior changes in this package.

## 0.1.1 - 2026-05-25

- Added inline comments to all painters, widgets, and styles
- Updated README with comprehensive widget API docs, overlay toggle guide, custom overlay examples, and theme presets
- Added example app section and release build warning to README

## 0.1.0 - 2026-05-24

- Initial release
- `VisionAiCameraView` — composite widget with camera preview and configurable overlays
- `HandLandmarkPainter` — draws 21-point hand skeleton (red dots + green lines)
- `HandBoundingBoxPainter` — draws rectangle around detected hands
- `FaceOverlayPainter` — draws face bounding box
- `FaceContourPainter` — draws 15 face contour polylines with dots
- `GestureLabel` — gesture name overlay with confidence
- `EmotionIndicator` — emotion name overlay with confidence
- `ConfidenceBar` — horizontal bar for score visualization
- Configurable `OverlayStyle` with `LandmarkStyle` and `LabelStyle`
