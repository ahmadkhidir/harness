import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/web/brave_search_provider.dart';
import 'package:harness/modules/web/duckduckgo_search_provider.dart';
import 'package:harness/modules/web/html_to_markdown.dart';
import 'package:harness/modules/web/http_fetch_provider.dart';
import 'package:harness/modules/web/tavily_search_provider.dart';
import 'package:harness/modules/web/web_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DuckDuckGoSearchProvider', () {
    test('decodes redirect links and extracts titles and snippets', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Flutter releases');
        return http.Response(
          '''
<html><body>
<div class="result">
  <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2Freleases">Flutter releases</a>
  <a class="result__snippet">Stable channel notes.</a>
</div>
<div class="result">
  <a class="result__a" href="https://dart.dev/releases">Dart releases</a>
  <a class="result__snippet">Dart SDK notes.</a>
</div>
</body></html>
''',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final provider = DuckDuckGoSearchProvider(client: client);
      final results = await provider.search('Flutter releases', maxResults: 2);

      expect(results, hasLength(2));
      expect(results.first.title, 'Flutter releases');
      expect(results.first.url, 'https://flutter.dev/releases');
      expect(results.first.snippet, 'Stable channel notes.');
      expect(results.last.url, 'https://dart.dev/releases');
    });

    test('respects maxResults', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<div class="result"><a class="result__a" href="https://a.dev">A</a></div>'
          '<div class="result"><a class="result__a" href="https://b.dev">B</a></div>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final provider = DuckDuckGoSearchProvider(client: client);
      final results = await provider.search('x', maxResults: 1);

      expect(results, hasLength(1));
      expect(results.single.url, 'https://a.dev');
    });
  });

  group('TavilySearchProvider', () {
    test('maps API results to snippets', () async {
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['api_key'], 'tvly-test');
        expect(body['query'], 'Dart');
        expect(body['max_results'], 3);

        return http.Response(
          json.encode({
            'results': [
              {
                'title': 'Dart',
                'url': 'https://dart.dev',
                'content': 'Dart language site.',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = TavilySearchProvider(apiKey: 'tvly-test', client: client);
      final results = await provider.search('Dart', maxResults: 3);

      expect(results.single.snippet, 'Dart language site.');
    });

    test('raises a bridge exception on non-2xx responses', () async {
      final client = MockClient((request) async => http.Response('nope', 401));
      final provider = TavilySearchProvider(apiKey: 'bad', client: client);

      expect(
        () => provider.search('Dart'),
        throwsA(isA<WebBridgeException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('BraveSearchProvider', () {
    test('maps web results and sends the subscription token', () async {
      final client = MockClient((request) async {
        expect(request.headers['X-Subscription-Token'], 'brave-key');
        expect(request.url.queryParameters['count'], '2');

        return http.Response(
          json.encode({
            'web': {
              'results': [
                {
                  'title': 'Flutter',
                  'url': 'https://flutter.dev',
                  'description': 'Build for any screen.',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = BraveSearchProvider(apiKey: 'brave-key', client: client);
      final results = await provider.search('Flutter', maxResults: 2);

      expect(results.single.title, 'Flutter');
      expect(results.single.snippet, 'Build for any screen.');
    });
  });

  group('extractMarkdownFromHtml', () {
    const html = '''
<html><body>
<nav>Menu</nav>
<article>
  <h1>Title</h1>
  <p>Hello <strong>world</strong>.</p>
  <ul><li>One</li><li>Two</li></ul>
  <pre><code>print(1)</code></pre>
</article>
<footer>Footer text</footer>
</body></html>
''';

    test('strips boilerplate and renders headings, emphasis, lists, and code', () {
      final result = extractMarkdownFromHtml(html);

      expect(result.truncated, isFalse);
      expect(result.markdown, contains('# Title'));
      expect(result.markdown, contains('Hello **world**.'));
      expect(result.markdown, contains('- One'));
      expect(result.markdown, contains('- Two'));
      expect(result.markdown, contains('```'));
      expect(result.markdown, contains('print(1)'));
      expect(result.markdown, isNot(contains('Menu')));
      expect(result.markdown, isNot(contains('Footer text')));
    });

    test('reports truncation when the character cap is exceeded', () {
      final result = extractMarkdownFromHtml(html, maxCharacters: 20);

      expect(result.truncated, isTrue);
      expect(result.markdown.length, lessThanOrEqualTo(20));
    });
  });

  group('HttpWebFetchProvider', () {
    test('fetches HTML and returns Markdown', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<html><body><article><h1>Hi</h1><p>Body text.</p></article></body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final provider = HttpWebFetchProvider(client: client);
      final result = await provider.fetchAsMarkdown('https://example.com/a');

      expect(result.url, 'https://example.com/a');
      expect(result.markdown, contains('# Hi'));
      expect(result.markdown, contains('Body text.'));
      expect(result.truncated, isFalse);
    });

    test('rejects loopback and private hosts before requesting', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('should not happen', 200);
      });

      final provider = HttpWebFetchProvider(client: client);

      await expectLater(
        () => provider.fetchAsMarkdown('http://127.0.0.1/admin'),
        throwsA(isA<WebBridgeException>()),
      );
      await expectLater(
        () => provider.fetchAsMarkdown('http://192.168.1.10/'),
        throwsA(isA<WebBridgeException>()),
      );

      expect(calls, 0);
    });

    test('rejects redirects to private hosts', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('', 302, headers: {
          'location': 'http://10.0.0.5/internal',
        });
      });

      final provider = HttpWebFetchProvider(client: client);

      await expectLater(
        () => provider.fetchAsMarkdown('https://example.com/a'),
        throwsA(isA<WebBridgeException>()),
      );
      expect(calls, 1);
    });

    test('aborts responses exceeding the byte cap', () async {
      final client = MockClient((request) async {
        return http.Response(
          'x' * 100,
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final provider = HttpWebFetchProvider(client: client, maxBytes: 10);

      await expectLater(
        () => provider.fetchAsMarkdown('https://example.com/a'),
        throwsA(isA<WebBridgeException>().having(
          (e) => e.message,
          'message',
          contains('limit'),
        )),
      );
    });

    test('surfaces HTTP error statuses', () async {
      final client = MockClient((request) async => http.Response('blocked', 403));
      final provider = HttpWebFetchProvider(client: client);

      await expectLater(
        () => provider.fetchAsMarkdown('https://example.com/a'),
        throwsA(isA<WebBridgeException>().having(
          (e) => e.statusCode,
          'statusCode',
          403,
        )),
      );
    });
  });
}
