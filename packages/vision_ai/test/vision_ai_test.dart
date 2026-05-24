import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_ai/vision_ai.dart';
import 'package:vision_ai/vision_ai_platform_interface.dart';
import 'package:vision_ai/vision_ai_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.visionai/commands'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'dispose') return null;
        if (methodCall.method == 'stopCamera') return null;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.visionai/commands'),
      null,
    );
  });

  final VisionAiPlatform initialPlatform = VisionAiPlatform.instance;

  test('VisionAiMethodChannel is the default instance', () {
    expect(initialPlatform, isInstanceOf<VisionAiMethodChannel>());
  });

  test('VisionAi requires at least one config', () {
    expect(
      () => VisionAi(),
      throwsA(isA<AssertionError>()),
    );
  });

  test('VisionAi.hand() creates hand-only detector', () {
    final vision = VisionAi.hand();
    expect(vision.isRunning, isFalse);
  });

  test('VisionAi.stop() is idempotent when not running', () async {
    final vision = VisionAi.hand();
    await vision.stop();
    await vision.stop();
    expect(vision.isRunning, isFalse);
  });

  test('VisionAi.dispose() is idempotent', () async {
    final vision = VisionAi.hand();
    await vision.dispose();
    await vision.dispose();
  });

  test('VisionAi.face() creates face-only detector', () {
    final vision = VisionAi.face();
    expect(vision.isRunning, isFalse);
  });

  test('VisionAi throws after dispose', () async {
    final vision = VisionAi.hand();
    await vision.dispose();
    expect(() => vision.results, throwsStateError);
  });

  group('Gesture enum', () {
    test('isRecognized returns false for none', () {
      expect(Gesture.none.isRecognized, isFalse);
    });

    test('isRecognized returns true for detected gestures', () {
      expect(Gesture.thumbsUp.isRecognized, isTrue);
      expect(Gesture.peace.isRecognized, isTrue);
      expect(Gesture.fist.isRecognized, isTrue);
    });
  });

  group('Emotion enum', () {
    test('isRecognized returns false for none', () {
      expect(Emotion.none.isRecognized, isFalse);
    });

    test('isRecognized returns true for detected emotions', () {
      expect(Emotion.happy.isRecognized, isTrue);
      expect(Emotion.surprised.isRecognized, isTrue);
    });
  });

  group('NormalizedLandmark', () {
    test('toOffset scales to canvas size', () {
      const landmark = NormalizedLandmark(0.5, 0.5, 0.0);
      final offset = landmark.toOffset(100, 200);
      expect(offset.dx, 50.0);
      expect(offset.dy, 100.0);
    });
  });

  group('CustomGesture', () {
    test('creates with finger state map', () {
      final gesture = CustomGesture(
        name: 'rock',
        fingerStates: {
          Finger.thumb: FingerState.closed,
          Finger.indexFinger: FingerState.extended,
          Finger.middle: FingerState.closed,
          Finger.ring: FingerState.closed,
          Finger.pinky: FingerState.extended,
        },
      );
      expect(gesture.name, 'rock');
      expect(gesture.fingerStates.length, 5);
      expect(gesture.fingerStates[Finger.indexFinger], FingerState.extended);
      expect(gesture.fingerStates[Finger.middle], FingerState.closed);
    });

    test('partial finger state map is valid', () {
      final gesture = CustomGesture(
        name: 'point',
        fingerStates: {
          Finger.indexFinger: FingerState.extended,
        },
      );
      expect(gesture.fingerStates.length, 1);
      expect(gesture.fingerStates[Finger.thumb], isNull);
    });
  });

  group('HandResult', () {
    test('toString includes gesture info', () {
      const result = HandResult(
        gesture: Gesture.thumbsUp,
        gestureConfidence: 0.94,
        landmarks: [],
        worldLandmarks: [],
        isLeftHand: true,
        handednessConfidence: 0.98,
        fingerStates: {
          Finger.thumb: FingerState.extended,
          Finger.indexFinger: FingerState.closed,
          Finger.middle: FingerState.closed,
          Finger.ring: FingerState.closed,
          Finger.pinky: FingerState.closed,
        },
      );
      expect(result.toString(), contains('thumbsUp'));
      expect(result.toString(), contains('0.94'));
    });
  });

  group('Finger enum', () {
    test('all fingers accounted for', () {
      expect(Finger.values.length, 5);
      expect(Finger.values, contains(Finger.thumb));
      expect(Finger.values, contains(Finger.indexFinger));
      expect(Finger.values, contains(Finger.middle));
      expect(Finger.values, contains(Finger.ring));
      expect(Finger.values, contains(Finger.pinky));
    });
  });

  group('VisionResult', () {
    test('hasHands and hasFaces return correctly', () {
      const result = VisionResult(
        hands: [],
        faces: [],
        timestampMs: 0,
        imageSize: Size(640, 480),
        inferenceTimeMs: 10,
      );
      expect(result.hasHands, isFalse);
      expect(result.hasFaces, isFalse);
      expect(result.primaryHand, isNull);
      expect(result.primaryFace, isNull);
    });
  });
}
