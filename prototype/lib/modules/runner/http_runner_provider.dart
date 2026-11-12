import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'runner_provider.dart';

/// [RunnerProvider] backed by an external HTTP sandbox.
///
/// Calls `POST {endpoint}/execute` with
/// `{"language", "code", "env", "timeoutSeconds"}` and expects
/// `{"exitCode", "stdout", "stderr", "executionTimeMs"}`.
class HttpRunnerProvider implements RunnerProvider {
  /// Base URL of the runner service.
  final String endpoint;

  /// Optional bearer token sent to the runner.
  final String? token;

  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Creates a provider for [endpoint].
  HttpRunnerProvider({required this.endpoint, this.token, this.client});

  @override
  Future<ScriptExecutionResult> executeScript({
    required String language,
    required String code,
    Map<String, String>? env,
    int timeoutSeconds = 30,
  }) async {
    final base = endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/execute');
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw RunnerException(
        'Invalid runner endpoint "$endpoint". Configure an absolute http(s) URL in Settings.',
      );
    }

    final clientToUse = client ?? http.Client();
    final timeout = Duration(seconds: timeoutSeconds);

    try {
      final response = await clientToUse
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token!.trim().isNotEmpty)
                'Authorization': 'Bearer ${token!.trim()}',
            },
            body: json.encode({
              'language': language,
              'code': code,
              if (env != null && env.isNotEmpty) 'env': env,
              'timeoutSeconds': timeoutSeconds,
            }),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RunnerException(
          'Runner responded HTTP ${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        throw const RunnerException('Runner returned a malformed response.');
      }

      return ScriptExecutionResult(
        exitCode: (decoded['exitCode'] as num?)?.toInt() ?? -1,
        stdout: (decoded['stdout'] ?? '').toString(),
        stderr: (decoded['stderr'] ?? '').toString(),
        executionTimeMs: (decoded['executionTimeMs'] as num?)?.toInt() ?? 0,
      );
    } on TimeoutException {
      throw RunnerException(
        'Runner timed out after ${timeoutSeconds}s at $base.',
      );
    } on http.ClientException catch (e) {
      throw RunnerException('Failed to reach runner at $base: ${e.message}');
    } on FormatException {
      throw const RunnerException('Runner returned invalid JSON.');
    }
  }
}
