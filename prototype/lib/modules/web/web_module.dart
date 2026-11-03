import 'dart:async';

import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../base/harness_module.dart';
import 'web_providers.dart';

/// Exposes external web search and page fetching as harness commands.
///
/// Implements FEAT-008:
/// - `web_search` queries the active [WebSearchProvider] (DuckDuckGo by default).
/// - `web_fetch` retrieves a page through [WebFetchProvider] and returns Markdown.
///
/// Provider construction is deferred to a factory so configuration changes made
/// on the settings screen take effect without rebuilding the engine.
class WebModule extends HarnessModule {
  /// Resolves the active search provider, or null when search is unavailable.
  ///
  /// Implementations may throw [WebBridgeException] to explain configuration
  /// problems such as a missing API key.
  final Future<WebSearchProvider?> Function() searchProviderFactory;

  /// Provider used by `web_fetch`.
  final WebFetchProvider fetchProvider;

  /// Creates a module with the supplied provider factory and fetcher.
  WebModule({
    required this.searchProviderFactory,
    required this.fetchProvider,
  });

  @override
  String get moduleName => 'web';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'web_search',
          description:
              'Searches the web for current information and returns ranked titles, URLs, and snippets.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'minLength': 1,
                'description': 'Search query text.',
              },
              'maxResults': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 10,
                'description': 'Maximum number of results to return. Defaults to 5.',
              },
            },
            'required': ['query'],
          },
        ),
        CommandDefinition(
          command: 'web_fetch',
          description:
              'Retrieves a webpage over HTTP(S) and returns its main content as readable Markdown.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'Absolute http or https URL to retrieve.',
              },
            },
            'required': ['url'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    switch (command) {
      case 'web_search':
        return _handleSearch(parameters);
      case 'web_fetch':
        return _handleFetch(parameters);
      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unrecognized web command: "$command".',
        );
    }
  }

  /// Validates and executes a `web_search` call.
  Future<SystemResponse> _handleSearch(Map<String, dynamic> parameters) async {
    final query = parameters['query'];
    if (query is! String || query.trim().isEmpty) {
      return _validationError(
        'web_search',
        'Missing or invalid "query". Provide a non-empty search query.',
      );
    }

    final rawMaxResults = parameters['maxResults'];
    final maxResults = rawMaxResults ?? 5;
    if (maxResults is! int || maxResults < 1 || maxResults > 10) {
      return _validationError(
        'web_search',
        'Invalid "maxResults": expected an integer between 1 and 10.',
      );
    }

    try {
      final provider = await searchProviderFactory();
      if (provider == null) {
        return SystemResponse.error(
          command: 'web_search',
          errorMessage:
              'Web search is not configured. Select a search provider in Settings.',
        );
      }

      final results = await provider.search(query.trim(), maxResults: maxResults);
      return SystemResponse.success(
        command: 'web_search',
        data: {
          'query': query.trim(),
          'results': results.map((result) => result.toJson()).toList(),
        },
      );
    } on TimeoutException {
      return SystemResponse.error(
        command: 'web_search',
        errorMessage: 'Web search timed out. Try a simpler query or another provider.',
      );
    } on WebBridgeException catch (e) {
      return SystemResponse.error(command: 'web_search', errorMessage: e.message);
    } catch (e) {
      return SystemResponse.error(
        command: 'web_search',
        errorMessage: 'Web search failed: $e',
      );
    }
  }

  /// Validates and executes a `web_fetch` call.
  Future<SystemResponse> _handleFetch(Map<String, dynamic> parameters) async {
    final url = parameters['url'];
    if (url is! String || url.trim().isEmpty) {
      return _validationError(
        'web_fetch',
        'Missing or invalid "url". Provide an absolute http(s) URL.',
      );
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return _validationError(
        'web_fetch',
        'Invalid URL "${url.trim()}": expected an absolute http or https URL.',
      );
    }

    try {
      final result = await fetchProvider.fetchAsMarkdown(uri.toString());
      return SystemResponse.success(
        command: 'web_fetch',
        data: result.toJson(),
      );
    } on TimeoutException {
      return SystemResponse.error(
        command: 'web_fetch',
        errorMessage: 'Timed out fetching ${uri.toString()}.',
      );
    } on WebBridgeException catch (e) {
      return SystemResponse.error(command: 'web_fetch', errorMessage: e.message);
    } catch (e) {
      return SystemResponse.error(
        command: 'web_fetch',
        errorMessage: 'Failed to fetch ${uri.toString()}: $e',
      );
    }
  }

  /// Builds a structured validation error response.
  SystemResponse _validationError(String command, String message) {
    return SystemResponse.error(
      command: command,
      errorMessage: 'Validation error for $command: $message',
    );
  }
}
