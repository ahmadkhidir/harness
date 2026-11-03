import 'package:harness/modules/runner/runner_provider.dart';
import 'package:harness/modules/web/web_providers.dart';

/// In-memory [WebSearchProvider] used by FEAT-008 tests.
class FakeWebSearchProvider implements WebSearchProvider {
  /// Results returned by [search].
  List<WebSearchResult> results;

  /// When set, [search] throws this instead of returning [results].
  Object? error;

  /// Query captured from the latest call.
  String? lastQuery;

  /// Maximum result count captured from the latest call.
  int? lastMaxResults;

  FakeWebSearchProvider({this.results = const [], this.error});

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    lastQuery = query;
    lastMaxResults = maxResults;
    if (error != null) throw error!;
    return results.take(maxResults).toList();
  }
}

/// In-memory [WebFetchProvider] used by FEAT-008 tests.
class FakeWebFetchProvider implements WebFetchProvider {
  /// Result returned by [fetchAsMarkdown].
  WebFetchResult result;

  /// When set, [fetchAsMarkdown] throws this instead of returning [result].
  Object? error;

  /// URL captured from the latest call.
  String? lastUrl;

  FakeWebFetchProvider({
    this.result = const WebFetchResult(
      url: 'https://example.com',
      markdown: '# Example',
      truncated: false,
    ),
    this.error,
  });

  @override
  Future<WebFetchResult> fetchAsMarkdown(String url) async {
    lastUrl = url;
    if (error != null) throw error!;
    return result;
  }
}

/// In-memory [RunnerProvider] used by FEAT-008 tests.
class FakeRunnerProvider implements RunnerProvider {
  /// Result returned by [executeScript].
  ScriptExecutionResult result;

  /// When set, [executeScript] throws this instead of returning [result].
  Object? error;

  /// Language captured from the latest call.
  String? lastLanguage;

  /// Code captured from the latest call.
  String? lastCode;

  /// Environment captured from the latest call.
  Map<String, String>? lastEnv;

  /// Timeout captured from the latest call.
  int? lastTimeoutSeconds;

  FakeRunnerProvider({
    this.result = const ScriptExecutionResult(
      exitCode: 0,
      stdout: 'ok',
      stderr: '',
      executionTimeMs: 5,
    ),
    this.error,
  });

  @override
  Future<ScriptExecutionResult> executeScript({
    required String language,
    required String code,
    Map<String, String>? env,
    int timeoutSeconds = 30,
  }) async {
    lastLanguage = language;
    lastCode = code;
    lastEnv = env;
    lastTimeoutSeconds = timeoutSeconds;
    if (error != null) throw error!;
    return result;
  }
}
