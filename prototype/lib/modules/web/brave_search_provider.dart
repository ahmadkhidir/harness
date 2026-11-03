import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'web_providers.dart';

/// Search provider backed by the Brave Web Search API.
class BraveSearchProvider implements WebSearchProvider {
  /// Brave subscription token resolved from the encrypted keystore.
  final String apiKey;

  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Per-request timeout.
  final Duration timeout;

  /// Creates a provider for [apiKey].
  BraveSearchProvider({
    required this.apiKey,
    this.client,
    this.timeout = const Duration(seconds: 20),
  });

  static final Uri _endpoint =
      Uri.parse('https://api.search.brave.com/res/v1/web/search');

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final clientToUse = client ?? http.Client();
    final uri = _endpoint.replace(queryParameters: {
      'q': query,
      'count': '$maxResults',
    });

    final response = await clientToUse.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'X-Subscription-Token': apiKey,
      },
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebBridgeException(
        'Brave search failed with HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final decoded = json.decode(response.body);
    final web = decoded is Map ? decoded['web'] : null;
    final results = web is Map ? web['results'] : null;
    if (results is! List) return const [];

    return results
        .whereType<Map>()
        .map(
          (item) => WebSearchResult(
            title: (item['title'] ?? '').toString(),
            url: (item['url'] ?? '').toString(),
            snippet: (item['description'] ?? '').toString(),
          ),
        )
        .where((result) => result.url.isNotEmpty)
        .take(maxResults)
        .toList();
  }
}
