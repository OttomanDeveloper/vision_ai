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
  final _commandChannel = const MethodChannel('com.visionai/commands');
  final _resultChannel = const EventChannel('com.visionai/results');

  Stream<VisionResult>? _resultStreamCache;

  @override
  Future<int> startCamera({
    required CameraConfig cameraConfig,
    HandConfig? handConfig,
    FaceConfig? faceConfig,
  }) async {
    final result = await _commandChannel.invokeMethod<int>('startCamera', {
      'cameraFacing': cameraConfig.facing.index,
      'resolution': cameraConfig.resolution.index,
      'enableHand': handConfig != null,
      'enableFace': faceConfig != null,
      if (handConfig != null) ...{
        'maxHands': handConfig.maxHands,
        'minDetectionConfidence': handConfig.minDetectionConfidence,
        'minPresenceConfidence': handConfig.minPresenceConfidence,
        'minTrackingConfidence': handConfig.minTrackingConfidence,
        'customGestures': handConfig.customGestures
            .map(
              (g) => {
                'name': g.name,
                'fingerStates': [
                  g.fingerStates[Finger.thumb]?.index ?? -1,
                  g.fingerStates[Finger.indexFinger]?.index ?? -1,
                  g.fingerStates[Finger.middle]?.index ?? -1,
                  g.fingerStates[Finger.ring]?.index ?? -1,
                  g.fingerStates[Finger.pinky]?.index ?? -1,
                ],
              },
            )
            .toList(),
      },
      if (faceConfig != null) ...{
        'detectEmotion': faceConfig.detectEmotion,
        'minFaceSize': faceConfig.minFaceSize,
        'enableFaceTracking': faceConfig.enableTracking,
        'minEmotionConfidence': faceConfig.minEmotionConfidence,
      },
    });
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
      });

  @override
  Future<void> updateFaceConfig(FaceConfig config) =>
      _commandChannel.invokeMethod<void>('updateFaceConfig', {
        'detectEmotion': config.detectEmotion,
        'minFaceSize': config.minFaceSize,
        'enableFaceTracking': config.enableTracking,
        'minEmotionConfidence': config.minEmotionConfidence,
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
    _resultStreamCache ??=
        _resultChannel.receiveBroadcastStream().map(_parseResult);
    return _resultStreamCache!;
  }

  VisionResult _parseResult(dynamic event) {
    final map = event as Map;
    return VisionResult(
      hands: _parseHandList(map['hands'] as List?),
      faces: _parseFaceList(map['faces'] as List?),
      timestampMs: map['timestamp'] as int,
      imageSize: Size(
        (map['imageWidth'] as int).toDouble(),
        (map['imageHeight'] as int).toDouble(),
      ),
      inferenceTimeMs: map['inferenceTime'] as int,
    );
  }

  List<HandResult> _parseHandList(List? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((e) => _parseHand(e as Map)).toList();
  }

  HandResult _parseHand(Map map) {
    final landmarkData = map['landmarks'] as Float64List;
    final worldData = map['worldLandmarks'] as Float64List;
    final fingerData = map['fingerStates'] as List;

    return HandResult(
      gesture: _parseGesture(map['gesture'] as String),
      customGestureName: map['customGestureName'] as String?,
      gestureConfidence: (map['gestureConfidence'] as num).toDouble(),
      landmarks: _toLandmarks(landmarkData),
      worldLandmarks: _toLandmarks(worldData),
      isLeftHand: map['isLeftHand'] as bool,
      handednessConfidence: (map['handednessConfidence'] as num).toDouble(),
      fingerStates: {
        for (var i = 0; i < Finger.values.length; i++)
          Finger.values[i]: (fingerData[i] as int) == 1
              ? FingerState.extended
              : FingerState.closed,
      },
    );
  }

  List<FaceResult> _parseFaceList(List? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((e) => _parseFace(e as Map)).toList();
  }

  FaceResult _parseFace(Map map) {
    final scores = map['emotionScores'] as Float64List;
    final bbox = map['boundingBox'] as List;
    final euler = map['eulerAngles'] as List;

    return FaceResult(
      emotion: _parseEmotion(map['emotion'] as String),
      emotionScores: {
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
      smilingProbability: (map['smilingProbability'] as num?)?.toDouble(),
      leftEyeOpenProbability:
          (map['leftEyeOpenProbability'] as num?)?.toDouble(),
      rightEyeOpenProbability:
          (map['rightEyeOpenProbability'] as num?)?.toDouble(),
      trackingId: (map['trackingId'] as int?) ?? -1,
    );
  }

  static List<NormalizedLandmark> _toLandmarks(Float64List data) {
    final landmarks = <NormalizedLandmark>[];
    for (var i = 0; i < data.length; i += 3) {
      landmarks.add(NormalizedLandmark(data[i], data[i + 1], data[i + 2]));
    }
    return landmarks;
  }

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
}
