import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'web_providers.dart';

/// Keyless default search provider backed by DuckDuckGo's HTML endpoint.
///
/// DuckDuckGo requires no API key, which keeps `web_search` usable out of the
/// box. Its HTML markup is scraped, so parsing is intentionally defensive: any
/// result missing a usable link is skipped rather than failing the whole call.
class DuckDuckGoSearchProvider implements WebSearchProvider {
  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Per-request timeout.
  final Duration timeout;

  /// Creates a provider around an optional [client].
  DuckDuckGoSearchProvider({
    this.client,
    this.timeout = const Duration(seconds: 20),
  });

  static final Uri _endpoint = Uri.parse('https://html.duckduckgo.com/html/');

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final uri = _endpoint.replace(queryParameters: {'q': query});
    final clientToUse = client ?? http.Client();

    final response = await clientToUse.get(
      uri,
      headers: const {
        'Accept': 'text/html',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 HarnessAgent/1.0',
      },
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebBridgeException(
        'DuckDuckGo search failed with HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final document = html_parser.parse(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );

    final results = <WebSearchResult>[];
    for (final element in document.querySelectorAll('.result')) {
      final link = element.querySelector('.result__a');
      if (link == null) continue;

      final url = _resolveResultUrl(link.attributes['href'] ?? '');
      if (url.isEmpty) continue;

      final title = link.text.trim();
      if (title.isEmpty) continue;

      final snippet =
          element.querySelector('.result__snippet')?.text.trim() ?? '';
      results.add(WebSearchResult(title: title, url: url, snippet: snippet));

      if (results.length >= maxResults) break;
    }

    return results;
  }

  /// Converts DuckDuckGo's redirect wrapper into the destination URL.
  ///
  /// Result links look like `//duckduckgo.com/l/?uddg=<encoded target>`. Direct
  /// links are returned unchanged.
  String _resolveResultUrl(String href) {
    var value = href.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) value = 'https:$value';

    final uri = Uri.tryParse(value);
    if (uri == null) return '';

    if (uri.host.endsWith('duckduckgo.com') && uri.path.startsWith('/l/')) {
      final target = uri.queryParameters['uddg'];
      if (target == null || target.isEmpty) return '';
      return Uri.decodeComponent(target);
    }

    return uri.toString();
  }
}
