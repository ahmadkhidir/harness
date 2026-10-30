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
  /// Fetches the target URL over HTTPS and converts the main article body into Markdown.
  Future<String> fetchAsMarkdown(String url);
}
