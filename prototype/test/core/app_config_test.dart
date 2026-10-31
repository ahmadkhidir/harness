import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/config/app_config.dart';

void main() {
  group('AppConfig Tests', () {
    test('huggingFaceToken returns configured token', () {
      final token = AppConfig.huggingFaceToken;
      expect(token, isNotNull);
      expect(token, startsWith('hf_'));
      expect(token, equals('hf_REDACTED'));
    });
  });
}

