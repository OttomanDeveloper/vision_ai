// Method channel serialization notes:
// - All data flows over standard MethodChannel types (Map, List, num, bool).
//   Float64List arrives from Kotlin DoubleArray and is consumed as-is; no copy needed.
// - FingerState uses a 3-value int encoding on the native side: 1=extended, 0=closed, -1=any
//   (wildcard for custom gesture configs). Dart's FingerState enum has no "any" concept so null
//   maps to -1 when sending and is never received back.
// - resultStream is cached so multiple listeners share one platform subscription.

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'src/models/config.dart';
import 'src/models/emotion.dart';
import 'src/models/face_result.dart';
import 'src/models/finger_state.dart';
import 'src/models/gesture.dart';
import 'src/models/hand_result.dart';
import 'src/models/landmark.dart';
import 'src/models/vision_result.dart';
import 'vision_ai_platform_interface.dart';

class VisionAiMethodChannel extends VisionAiPlatform {
  // Commands (start, stop, config updates) are fire-and-reply on this channel.
  final _commandChannel = const MethodChannel('com.visionai/commands');
  // Results stream continuously from native; one-directional native→Dart.
  final _resultChannel = const EventChannel('com.visionai/results');

  // Lazily created; null until the first listener subscribes via [resultStream].
  Stream<VisionResult>? _resultStreamCache;

  @override
  Future<int> startCamera({
    required CameraConfig cameraConfig,
    HandConfig? handConfig,
    FaceConfig? faceConfig,
  }) async {
    // Clamp to 1-60 if set, 0 means no throttle
    final maxResults = cameraConfig.maxResultsPerSecond <= 0
        ? 0
        : cameraConfig.maxResultsPerSecond.clamp(1, 60);

    final result = await _commandChannel.invokeMethod<int>('startCamera', {
      'cameraFacing': cameraConfig.facing.index,
      'resolution': cameraConfig.resolution.index,
      'maxResultsPerSecond': maxResults,
      'enableHand': handConfig != null,
      'enableFace': faceConfig != null,
      if (handConfig != null) ...{
        'maxHands': handConfig.maxHands,
        'minDetectionConfidence': handConfig.minDetectionConfidence,
        'minPresenceConfidence': handConfig.minPresenceConfidence,
        'minTrackingConfidence': handConfig.minTrackingConfidence,
        // Each custom gesture serializes its fingerStates in thumb→pinky order.
        'customGestures': handConfig.customGestures
            .map(
              (g) => {
                'name': g.name,
                'fingerStates': [
                  _fingerStateToNative(g.fingerStates[Finger.thumb]),
                  _fingerStateToNative(g.fingerStates[Finger.indexFinger]),
                  _fingerStateToNative(g.fingerStates[Finger.middle]),
                  _fingerStateToNative(g.fingerStates[Finger.ring]),
                  _fingerStateToNative(g.fingerStates[Finger.pinky]),
                ],
              },
            )
            .toList(),
        ..._serializeGestureFilters(handConfig),
      },
      if (faceConfig != null) ...{
        'detectEmotion': faceConfig.detectEmotion,
        'detectLandmarks': faceConfig.detectLandmarks,
        'detectContours': faceConfig.detectContours,
        'minFaceSize': faceConfig.minFaceSize,
        'enableFaceTracking': faceConfig.enableTracking,
        'minEmotionConfidence': faceConfig.minEmotionConfidence,
        'accurateMode': faceConfig.accurateMode,
      },
    });
    // result! is safe: native always returns an int on success, throws on failure.
    return result!;
  }

  @override
  Future<void> stopCamera() =>
      _commandChannel.invokeMethod<void>('stopCamera');

  @override
  Future<void> updateHandConfig(HandConfig config) =>
      _commandChannel.invokeMethod<void>('updateHandConfig', {
        'maxHands': config.maxHands,
        'minDetectionConfidence': config.minDetectionConfidence,
        'minPresenceConfidence': config.minPresenceConfidence,
        'minTrackingConfidence': config.minTrackingConfidence,
        // Full replacement — native discards old custom gesture list entirely.
        'customGestures': config.customGestures
            .map(
              (g) => {
                'name': g.name,
                'fingerStates': [
                  _fingerStateToNative(g.fingerStates[Finger.thumb]),
                  _fingerStateToNative(g.fingerStates[Finger.indexFinger]),
                  _fingerStateToNative(g.fingerStates[Finger.middle]),
                  _fingerStateToNative(g.fingerStates[Finger.ring]),
                  _fingerStateToNative(g.fingerStates[Finger.pinky]),
                ],
              },
            )
            .toList(),
        ..._serializeGestureFilters(config),
      });

  @override
  Future<void> updateFaceConfig(FaceConfig config) =>
      _commandChannel.invokeMethod<void>('updateFaceConfig', {
        'detectEmotion': config.detectEmotion,
        'detectContours': config.detectContours,
        'minFaceSize': config.minFaceSize,
        'enableFaceTracking': config.enableTracking,
        'minEmotionConfidence': config.minEmotionConfidence,
        'accurateMode': config.accurateMode,
      });

  @override
  Future<void> switchCamera(CameraFacing facing) =>
      _commandChannel.invokeMethod<void>('switchCamera', {
        'facing': facing.index,
      });

  @override
  Future<void> dispose() =>
      _commandChannel.invokeMethod<void>('dispose');

  @override
  Stream<VisionResult> get resultStream {
    // Cache ensures all Dart listeners share a single EventChannel subscription.
    _resultStreamCache ??=
        _resultChannel.receiveBroadcastStream().map(_parseResult);
    return _resultStreamCache!;
  }

  VisionResult _parseResult(dynamic event) {
    final map = event as Map;
    return VisionResult(
      hands: _parseHandList(map['hands'] as List?),
      faces: _parseFaceList(map['faces'] as List?),
      // Milliseconds since epoch at the moment native captured the frame.
      timestampMs: map['timestamp'] as int,
      imageSize: Size(
        (map['imageWidth'] as int).toDouble(),
        (map['imageHeight'] as int).toDouble(),
      ),
      // Time spent in the ML inference step only, not including camera capture.
      inferenceTimeMs: map['inferenceTime'] as int,
    );
  }

  List<HandResult> _parseHandList(List? raw) {
    // Returns const empty to avoid allocating when no hands are detected.
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((e) => _parseHand(e as Map)).toList();
  }

  HandResult _parseHand(Map map) {
    // Float64List from Kotlin DoubleArray; stride-3 packed as [x, y, z, x, y, z, ...].
    final landmarkData = map['landmarks'] as Float64List;
    final worldData = map['worldLandmarks'] as Float64List;
    // int list; native sends 1=extended, 0=closed only (never -1 in results).
    final fingerData = map['fingerStates'] as List;

    return HandResult(
      gesture: _parseGesture(map['gesture'] as String),
      customGestureName: map['customGestureName'] as String?,
      gestureConfidence: (map['gestureConfidence'] as num).toDouble(),
      landmarks: _toLandmarks(landmarkData),
      worldLandmarks: _toWorldLandmarks(worldData),
      isLeftHand: map['isLeftHand'] as bool,
      handednessConfidence: (map['handednessConfidence'] as num).toDouble(),
      fingerStates: {
        // Finger.values order matches thumb→pinky, matching native array packing.
        for (var i = 0; i < Finger.values.length; i++)
          Finger.values[i]: (fingerData[i] as int) == 1
              ? FingerState.extended
              : FingerState.closed,
      },
    );
  }

  List<FaceResult> _parseFaceList(List? raw) {
    // Returns const empty to avoid allocating when no faces are detected.
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((e) => _parseFace(e as Map)).toList();
  }

  FaceResult _parseFace(Map map) {
    // Float64List; index order matches Emotion enum declaration (angry=0 … neutral=6).
    final scores = map['emotionScores'] as Float64List;
    // [left, top, right, bottom] in image pixel coordinates from ML Kit.
    final bbox = map['boundingBox'] as List;
    // [X=pitch, Y=yaw, Z=roll] in degrees; positive values defined per ML Kit convention.
    final euler = map['eulerAngles'] as List;

    return FaceResult(
      emotion: _parseEmotion(map['emotion'] as String),
      emotionScores: {
        // Explicit mapping keeps enum-to-index contract visible and safe to refactor.
        Emotion.angry: scores[0],
        Emotion.disgusted: scores[1],
        Emotion.fearful: scores[2],
        Emotion.happy: scores[3],
        Emotion.sad: scores[4],
        Emotion.surprised: scores[5],
        Emotion.neutral: scores[6],
      },
      emotionConfidence: (map['emotionConfidence'] as num).toDouble(),
      boundingBox: Rect.fromLTRB(
        (bbox[0] as num).toDouble(),
        (bbox[1] as num).toDouble(),
        (bbox[2] as num).toDouble(),
        (bbox[3] as num).toDouble(),
      ),
      headEulerAngleX: (euler[0] as num).toDouble(),
      headEulerAngleY: (euler[1] as num).toDouble(),
      headEulerAngleZ: (euler[2] as num).toDouble(),
      // Nullable — only present when ML Kit's classification model is active.
      smilingProbability: (map['smilingProbability'] as num?)?.toDouble(),
      leftEyeOpenProbability:
          (map['leftEyeOpenProbability'] as num?)?.toDouble(),
      rightEyeOpenProbability:
          (map['rightEyeOpenProbability'] as num?)?.toDouble(),
      // -1 when tracking is disabled or face was first detected this frame.
      trackingId: (map['trackingId'] as int?) ?? -1,
      landmarks: _parseLandmarkPoints(map['landmarkPoints']),
      contours: _parseContours(map),
    );
  }

  static List<Offset>? _parseLandmarkPoints(dynamic raw) {
    if (raw == null) return null;
    // Float64List branch avoids a redundant copy when native sends typed data directly.
    final Float64List pts = raw is Float64List
        ? raw
        : Float64List.fromList(
            (raw as List).map((e) => (e as num).toDouble()).toList());
    final list = <Offset>[];
    // Stride-2 packed: [x0, y0, x1, y1, ...] in image pixel coordinates.
    for (var i = 0; i < pts.length; i += 2) {
      list.add(Offset(pts[i], pts[i + 1]));
    }
    return list;
  }

  static List<List<Offset>>? _parseContours(Map map) {
    final points = map['contourPoints'];
    // contourSizes tells how many points belong to each contour group.
    final sizes = map['contourSizes'] as List?;
    if (points == null || sizes == null) return null;

    // Float64List branch avoids a redundant copy when native sends typed data directly.
    final Float64List pts = points is Float64List
        ? points
        : Float64List.fromList(
            (points as List).map((e) => (e as num).toDouble()).toList());

    final contours = <List<Offset>>[];
    var offset = 0;
    for (final size in sizes) {
      final count = size as int;
      final group = <Offset>[];
      // Each point occupies two consecutive float64 values (x, y).
      for (var i = 0; i < count; i++) {
        group.add(Offset(pts[offset], pts[offset + 1]));
        offset += 2;
      }
      // Skip degenerate empty contour groups that native may send.
      if (group.isNotEmpty) contours.add(group);
    }
    return contours;
  }

  // Stride-3 unpacking: native packs as [x, y, z, x, y, z, ...] for all 21 points.
  static List<NormalizedLandmark> _toLandmarks(Float64List data) {
    final landmarks = <NormalizedLandmark>[];
    for (var i = 0; i < data.length; i += 3) {
      landmarks.add(NormalizedLandmark(data[i], data[i + 1], data[i + 2]));
    }
    return landmarks;
  }

  // Stride-3 unpacking: same layout as _toLandmarks but values are in meters.
  static List<WorldLandmark> _toWorldLandmarks(Float64List data) {
    final landmarks = <WorldLandmark>[];
    for (var i = 0; i < data.length; i += 3) {
      landmarks.add(WorldLandmark(data[i], data[i + 1], data[i + 2]));
    }
    return landmarks;
  }

  // Maps native MediaPipe string labels to the Dart enum; unknown labels → custom.
  static Gesture _parseGesture(String name) => switch (name) {
        'Closed_Fist' => Gesture.fist,
        'Open_Palm' => Gesture.openHand,
        'Victory' => Gesture.peace,
        'Thumb_Up' => Gesture.thumbsUp,
        'Thumb_Down' => Gesture.thumbsDown,
        'Pointing_Up' => Gesture.pointingUp,
        'ILoveYou' => Gesture.iLoveYou,
        'ok' => Gesture.ok,
        'one' => Gesture.one,
        'two' => Gesture.two,
        'three' => Gesture.three,
        'four' => Gesture.four,
        'five' => Gesture.five,
        'None' => Gesture.none,
        _ => Gesture.custom,
      };

  // Maps native emotion label strings; unrecognized labels → none (classifier not run).
  static Emotion _parseEmotion(String name) => switch (name) {
        'happy' => Emotion.happy,
        'sad' => Emotion.sad,
        'angry' => Emotion.angry,
        'surprised' => Emotion.surprised,
        'disgusted' => Emotion.disgusted,
        'fearful' => Emotion.fearful,
        'neutral' => Emotion.neutral,
        _ => Emotion.none,
      };

  // Kotlin uses 1=extended, 0=closed, -1=any
  static int _fingerStateToNative(FingerState? state) => switch (state) {
        FingerState.extended => 1,
        FingerState.closed => 0,
        // null means the finger was omitted from CustomGesture.fingerStates → wildcard.
        null => -1,
      };

  // Omits keys entirely when lists/maps are empty to avoid no-op native processing.
  static Map<String, Object> _serializeGestureFilters(HandConfig config) {
    final map = <String, Object>{};
    if (config.allowedGestures != null && config.allowedGestures!.isNotEmpty) {
      map['allowedGestures'] =
          config.allowedGestures!.map(_gestureToNative).toList();
    }
    if (config.deniedGestures != null && config.deniedGestures!.isNotEmpty) {
      map['deniedGestures'] =
          config.deniedGestures!.map(_gestureToNative).toList();
    }
    if (config.gestureThresholds != null &&
        config.gestureThresholds!.isNotEmpty) {
      // Native map key is the string label, value is the double threshold [0.0, 1.0].
      map['gestureThresholds'] = {
        for (final e in config.gestureThresholds!.entries)
          _gestureToNative(e.key): e.value,
      };
    }
    return map;
  }

  // Inverse of _parseGesture; must stay in sync whenever new gestures are added.
  static String _gestureToNative(Gesture g) => switch (g) {
        Gesture.fist => 'Closed_Fist',
        Gesture.openHand => 'Open_Palm',
        Gesture.peace => 'Victory',
        Gesture.thumbsUp => 'Thumb_Up',
        Gesture.thumbsDown => 'Thumb_Down',
        Gesture.pointingUp => 'Pointing_Up',
        Gesture.iLoveYou => 'ILoveYou',
        Gesture.ok => 'ok',
        Gesture.one => 'one',
        Gesture.two => 'two',
        Gesture.three => 'three',
        Gesture.four => 'four',
        Gesture.five => 'five',
        Gesture.custom => 'custom',
        Gesture.none => 'None',
      };
}
