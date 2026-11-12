import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/network_guard.dart';

void main() {
  group('normalizeHostEntry', () {
    test('normalizes exact hosts and host:port entries', () {
      expect(normalizeHostEntry('API.Example.com'), 'api.example.com');
      expect(
        normalizeHostEntry(' API.Example.com:8443 '),
        'api.example.com:8443',
      );
    });

    test('accepts wildcard entries', () {
      expect(normalizeHostEntry('*'), '*');
      expect(normalizeHostEntry(' *.Example.com '), '*.example.com');
      expect(normalizeHostEntry('api.*.com:443'), 'api.*.com:443');
      expect(normalizeHostEntry('*:*'), '*:*');
    });

    test('rejects malformed and unsafe entries', () {
      expect(normalizeHostEntry('https://example.com/path'), isNull);
      expect(normalizeHostEntry('bad host'), isNull);
      expect(normalizeHostEntry('*:99999'), isNull);
      expect(normalizeHostEntry('*foo/bar'), isNull);
      expect(normalizeHostEntry('..example.com'), isNull);
      expect(normalizeHostEntry('example..com'), isNull);
      expect(normalizeHostEntry(''), isNull);
    });
  });

  group('isHostAllowed', () {
    test('matches exact hosts and ports', () {
      expect(
        isHostAllowed('api.example.com', null, const ['api.example.com']),
        isTrue,
      );
      expect(
        isHostAllowed('api.example.com', 8443, const ['api.example.com:8443']),
        isTrue,
      );
      expect(
        isHostAllowed('api.example.com', 443, const ['api.example.com:8443']),
        isFalse,
      );
    });

    test('a single wildcard allows every host and port', () {
      expect(isHostAllowed('anything.example', null, const ['*']), isTrue);
      expect(isHostAllowed('127.0.0.1', 8080, const ['*']), isTrue);
    });

    test('subdomain wildcards match labels but not the apex', () {
      const allowed = ['*.example.com'];
      expect(isHostAllowed('api.example.com', null, allowed), isTrue);
      expect(isHostAllowed('a.b.example.com', null, allowed), isTrue);
      expect(isHostAllowed('example.com', null, allowed), isFalse);
      expect(isHostAllowed('notexample.com', null, allowed), isFalse);
      expect(isHostAllowed('evil-example.com', null, allowed), isFalse);
    });

    test('wildcards can sit in the middle of a host', () {
      const allowed = ['api.*.com'];
      expect(isHostAllowed('api.dev.com', null, allowed), isTrue);
      expect(isHostAllowed('api.example.io', null, allowed), isFalse);
    });

    test('wildcard entries still honor an explicit port', () {
      expect(isHostAllowed('any.example', 8443, const ['*:8443']), isTrue);
      expect(isHostAllowed('any.example', 443, const ['*:8443']), isFalse);
      expect(
        isHostAllowed('api.example.com', 8443, const ['*.example.com:8443']),
        isTrue,
      );
      expect(
        isHostAllowed('api.example.com', 443, const ['*.example.com:8443']),
        isFalse,
      );
    });
  });
}
