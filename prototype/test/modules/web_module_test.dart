import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/web/web_module.dart';
import 'package:harness/modules/web/web_providers.dart';

import '../mocks/fake_bridges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebSearchProvider searchProvider;
  late FakeWebFetchProvider fetchProvider;
  late WebModule module;

  setUp(() {
    searchProvider = FakeWebSearchProvider(results: const [
      WebSearchResult(
        title: 'Flutter releases',
        url: 'https://flutter.dev/releases',
        snippet: 'Stable channel notes.',
      ),
      WebSearchResult(
        title: 'Dart releases',
        url: 'https://dart.dev/releases',
        snippet: 'Dart SDK notes.',
      ),
    ]);
    fetchProvider = FakeWebFetchProvider();
    module = WebModule(
      searchProviderFactory: () async => searchProvider,
      fetchProvider: fetchProvider,
    );
  });

  group('WebModule - FEAT-008', () {
    test('web_search returns structured results', () async {
      final response = await module.executeCommand('web_search', {
        'query': 'Flutter releases',
        'maxResults': 1,
      });

      expect(response.isSuccess, isTrue);
      expect(searchProvider.lastQuery, 'Flutter releases');
      expect(searchProvider.lastMaxResults, 1);

      final data = response.data as Map<String, dynamic>;
      expect(data['query'], 'Flutter releases');
      expect((data['results'] as List), hasLength(1));
      expect(
        (data['results'] as List).first,
        containsPair('url', 'https://flutter.dev/releases'),
      );
    });

    test('web_search rejects empty queries before calling the provider', () async {
      final response = await module.executeCommand('web_search', {'query': '  '});

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('"query"'));
      expect(searchProvider.lastQuery, isNull);
    });

    test('web_search rejects out-of-range maxResults', () async {
      final response = await module.executeCommand('web_search', {
        'query': 'Dart',
        'maxResults': 11,
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('maxResults'));
    });

    test('web_search reports a missing provider key as an error observation', () async {
      final moduleWithNoKey = WebModule(
        searchProviderFactory: () async => throw const WebBridgeException(
          'Tavily search is selected but no API key is configured.',
        ),
        fetchProvider: fetchProvider,
      );

      final response = await moduleWithNoKey.executeCommand(
        'web_search',
        {'query': 'Dart'},
      );

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('no API key'));
    });

    test('web_search surfaces provider timeouts', () async {
      searchProvider.error = TimeoutException('slow');

      final response = await module.executeCommand(
        'web_search',
        {'query': 'Dart'},
      );

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('timed out'));
    });

    test('web_fetch returns Markdown from the provider', () async {
      fetchProvider.result = const WebFetchResult(
        url: 'https://example.com/article',
        markdown: '# Article\n\nBody.',
        truncated: false,
      );

      final response = await module.executeCommand('web_fetch', {
        'url': 'https://example.com/article',
      });

      expect(response.isSuccess, isTrue);
      expect(fetchProvider.lastUrl, 'https://example.com/article');
      final data = response.data as Map<String, dynamic>;
      expect(data['markdown'], contains('# Article'));
      expect(data['truncated'], isFalse);
    });

    test('web_fetch rejects non-http URLs before fetching', () async {
      final response = await module.executeCommand('web_fetch', {
        'url': 'file:///etc/passwd',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('http'));
      expect(fetchProvider.lastUrl, isNull);
    });

    test('web_fetch reports HTTP errors from the provider', () async {
      fetchProvider.error = const WebBridgeException(
        'HTTP 403 fetching https://example.com.',
        statusCode: 403,
      );

      final response = await module.executeCommand('web_fetch', {
        'url': 'https://example.com',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('403'));
    });
  });
}
