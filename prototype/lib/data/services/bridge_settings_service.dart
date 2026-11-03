import 'package:http/http.dart' as http;

import '../../modules/runner/http_runner_provider.dart';
import '../../modules/runner/runner_provider.dart';
import '../../modules/web/brave_search_provider.dart';
import '../../modules/web/duckduckgo_search_provider.dart';
import '../../modules/web/http_fetch_provider.dart';
import '../../modules/web/tavily_search_provider.dart';
import '../../modules/web/web_providers.dart';
import '../database/app_database.dart';
import '../secure_storage/key_storage_service.dart';

/// Resolves and persists external bridge configuration for FEAT-008.
///
/// Factories are called per command execution so changes saved on the settings
/// screen apply without rebuilding the engine.
class BridgeSettingsService {
  /// Configuration store for the selected provider and runner endpoint.
  final AppDatabase database;

  /// Encrypted key storage for Tavily and Brave credentials.
  final KeyStorageService keyStorage;

  /// Optional HTTP client shared by bridge providers (injectable for tests).
  final http.Client? client;

  /// Creates a service around the supplied stores.
  BridgeSettingsService({
    required this.database,
    required this.keyStorage,
    this.client,
  });

  /// Builds the active [WebSearchProvider].
  ///
  /// Returns DuckDuckGo when no provider was explicitly selected. Throws
  /// [WebBridgeException] when Tavily or Brave is selected without its key.
  Future<WebSearchProvider?> createSearchProvider() async {
    final providerId = await database.getSearchProviderId();

    switch (providerId) {
      case 'tavily':
        final key = await keyStorage.getApiKey('tavily');
        if (key == null || key.trim().isEmpty) {
          throw const WebBridgeException(
            'Tavily search is selected but no API key is configured. Add one in Settings.',
          );
        }
        return TavilySearchProvider(apiKey: key.trim(), client: client);

      case 'brave':
        final key = await keyStorage.getApiKey('brave');
        if (key == null || key.trim().isEmpty) {
          throw const WebBridgeException(
            'Brave search is selected but no API key is configured. Add one in Settings.',
          );
        }
        return BraveSearchProvider(apiKey: key.trim(), client: client);

      case 'duckduckgo':
      default:
        return DuckDuckGoSearchProvider(client: client);
    }
  }

  /// Builds the configured external runner, or null when no endpoint is saved.
  Future<RunnerProvider?> createRunnerProvider() async {
    final endpoint = await database.getRunnerEndpoint();
    if (endpoint == null) return null;
    return HttpRunnerProvider(endpoint: endpoint, client: client);
  }

  /// Builds the provider used by `web_fetch`.
  WebFetchProvider createFetchProvider() => HttpWebFetchProvider(client: client);

  /// Returns the hosts approved for `http_request`.
  Future<List<String>> getAllowedHosts() => database.getAllowedHosts();
}
