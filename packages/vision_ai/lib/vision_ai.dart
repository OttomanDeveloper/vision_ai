// Core: camera + ML pipeline, all native processing, results via EventChannel.
// Detectors: standalone Dart classes that consume FaceResult streams. No native code.
// Models: data classes for results, config, enums. Serialized across platform channel.
// UI: separate package (vision_ai_flutter) with painters and overlay widgets.

// Dart-side detectors — no platform channel involvement.
export 'src/attention_scorer.dart';
export 'src/blink_detector.dart';
export 'src/face_distance_estimator.dart';
export 'src/hand_motion_tracker.dart';
export 'src/head_gesture_detector.dart';
// Config and model types shared by platform channel serialization.
export 'src/models/config.dart';
export 'src/models/emotion.dart';
export 'src/models/face_result.dart';
export 'src/models/finger_state.dart';
export 'src/models/gesture.dart';
export 'src/models/hand_result.dart';
export 'src/models/landmark.dart';
export 'src/models/vision_result.dart';
// Multi-hand and two-hand coordination helpers.
export 'src/two_hand_detector.dart';
// Primary entry point for starting the camera pipeline.
export 'src/vision_ai_controller.dart';
