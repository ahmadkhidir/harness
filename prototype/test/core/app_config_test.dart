import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/config/app_config.dart';

void main() {
  group('AppConfig Tests', () {
    test('huggingFaceToken is null or a well-formed token', () {
      final token = AppConfig.huggingFaceToken;

      // The token is injected at build time with --dart-define-from-file=.env.
      // When it is absent, the getter must report null rather than an empty
      // string, so callers can treat model downloads as unauthenticated.
      if (token == null) {
        expect(token, isNull);
        return;
      }

      expect(token, startsWith('hf_'));
      expect(token, isNot(contains(' ')));
    });
  });
}
