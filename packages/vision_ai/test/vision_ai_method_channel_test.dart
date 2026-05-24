import 'package:flutter_test/flutter_test.dart';
import 'package:vision_ai/vision_ai_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VisionAiMethodChannel can be instantiated', () {
    final channel = VisionAiMethodChannel();
    expect(channel, isNotNull);
  });
}
