import 'package:flutter_test/flutter_test.dart';
import 'package:harness/data/database/app_database.dart';

void main() {
  group('AppDatabase bridge settings', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    test('defaults the search provider to DuckDuckGo', () async {
      expect(await database.getSearchProviderId(), 'duckduckgo');
    });

    test('persists and normalizes allowed hosts', () async {
      await database.setAllowedHosts(const [
        'API.Example.com',
        'api.example.com:8443',
        'api.example.com',
      ]);

      expect(await database.getAllowedHosts(), const [
        'api.example.com',
        'api.example.com:8443',
      ]);
    });

    test('persists wildcard allowed host patterns', () async {
      await database.setAllowedHosts(const ['*', '*.example.com']);

      expect(await database.getAllowedHosts(), const ['*', '*.example.com']);
    });

    test('rejects invalid allowed host entries', () async {
      expect(
        () => database.setAllowedHosts(const ['https://example.com/path']),
        throwsArgumentError,
      );
      expect(
        () => database.setAllowedHosts(const ['bad host']),
        throwsArgumentError,
      );
    });

    test('validates the runner endpoint', () async {
      await database.setRunnerEndpoint('https://runner.example.com');
      expect(await database.getRunnerEndpoint(), 'https://runner.example.com');

      await database.setRunnerEndpoint(null);
      expect(await database.getRunnerEndpoint(), isNull);

      expect(
        () => database.setRunnerEndpoint('not-a-url'),
        throwsArgumentError,
      );
    });
  });
}
