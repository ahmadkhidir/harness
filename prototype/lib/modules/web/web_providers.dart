/// Structured web search hit.
class WebSearchResult {
  /// Webpage or article title.
  final String title;

  /// Webpage canonical URL.
  final String url;

  /// Summary snippet of the search result.
  final String snippet;

  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

/// Structured result of fetching and converting a webpage.
class WebFetchResult {
  /// The requested URL.
  final String url;

  /// Readable Markdown extracted from the page body.
  final String markdown;

  /// True when the extracted Markdown exceeded the configured length cap.
  final bool truncated;

  const WebFetchResult({
    required this.url,
    required this.markdown,
    required this.truncated,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'markdown': markdown,
        'truncated': truncated,
      };
}

/// Failure raised by a web bridge provider.
///
/// Carries an HTTP status when the remote server rejected the request so the
/// module can produce a model-readable error observation.
class WebBridgeException implements Exception {
  /// Human- and model-readable failure description.
  final String message;

  /// HTTP status code when the failure originated from a remote response.
  final int? statusCode;

  const WebBridgeException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Abstract contract for web search providers (Tavily, Brave, DuckDuckGo).
abstract class WebSearchProvider {
  /// Queries the web and returns ranked result snippets.
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  });
}

/// Abstract contract for fetching and stripping webpages into readable Markdown.
abstract class WebFetchProvider {
  /// Fetches the target URL over HTTP(S) and converts the main article body into Markdown.
  Future<WebFetchResult> fetchAsMarkdown(String url);
}
