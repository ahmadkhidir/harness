import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'web_providers.dart';

/// Search provider backed by the Tavily search API.
class TavilySearchProvider implements WebSearchProvider {
  /// Tavily API key resolved from the encrypted keystore.
  final String apiKey;

  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Per-request timeout.
  final Duration timeout;

  /// Creates a provider for [apiKey].
  TavilySearchProvider({
    required this.apiKey,
    this.client,
    this.timeout = const Duration(seconds: 20),
  });

  static final Uri _endpoint = Uri.parse('https://api.tavily.com/search');

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final clientToUse = client ?? http.Client();

    final response = await clientToUse.post(
      _endpoint,
      headers: const {'Content-Type': 'application/json'},
      body: json.encode({
        'api_key': apiKey,
        'query': query,
        'max_results': maxResults,
      }),
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebBridgeException(
        'Tavily search failed with HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final decoded = json.decode(response.body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return const [];

    return results
        .whereType<Map>()
        .map(
          (item) => WebSearchResult(
            title: (item['title'] ?? '').toString(),
            url: (item['url'] ?? '').toString(),
            snippet: (item['content'] ?? item['snippet'] ?? '').toString(),
          ),
        )
        .where((result) => result.url.isNotEmpty)
        .take(maxResults)
        .toList();
  }
}
