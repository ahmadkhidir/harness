import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/runner/http_runner_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends the bearer token and parses the execution result', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'exitCode': 0,
          'stdout': '4\n',
          'stderr': '',
          'executionTimeMs': 12,
        }),
        200,
      );
    });

    final provider = HttpRunnerProvider(
      endpoint: 'https://runner.example.com/',
      token: 'secret-token',
      client: client,
    );

    final result = await provider.executeScript(
      language: 'python',
      code: 'print(2 + 2)',
      timeoutSeconds: 10,
    );

    expect(captured.url.toString(), 'https://runner.example.com/execute');
    expect(captured.headers['Authorization'], 'Bearer secret-token');
    expect(captured.headers['Content-Type'], contains('application/json'));

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['language'], 'python');
    expect(body['code'], 'print(2 + 2)');
    expect(body['timeoutSeconds'], 10);

    expect(result.exitCode, 0);
    expect(result.stdout, '4\n');
    expect(result.stderr, isEmpty);
    expect(result.executionTimeMs, 12);
  });

  test('omits the authorization header when no token is configured', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'exitCode': 1,
          'stdout': '',
          'stderr': 'boom',
          'executionTimeMs': 3,
        }),
        200,
      );
    });

    final provider = HttpRunnerProvider(
      endpoint: 'http://localhost:8080',
      client: client,
    );

    await provider.executeScript(language: 'bash', code: 'exit 1');

    expect(captured.headers.containsKey('Authorization'), isFalse);
  });
}
