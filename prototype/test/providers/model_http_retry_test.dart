import 'package:flutter_test/flutter_test.dart';
import 'package:harness/providers/model_http_retry.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final url = Uri.parse('https://example.com/v1/chat/completions');

  Future<http.Response> run(
    http.Client client, {
    int maxAttempts = ModelHttpRetry.defaultMaxAttempts,
    List<ModelRetryEvent>? events,
  }) {
    return ModelHttpRetry.post(
      client: client,
      url: url,
      headers: const {'Content-Type': 'application/json'},
      body: '{}',
      provider: 'test',
      maxAttempts: maxAttempts,
      wait: (_) async {},
      onRetry: events?.add,
    );
  }

  test('retries a 429 and succeeds', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls < 3) {
        return http.Response('overloaded', 429);
      }
      return http.Response('ok', 200);
    });

    final events = <ModelRetryEvent>[];
    final response = await run(client, events: events);

    expect(response.statusCode, 200);
    expect(calls, 3);
    expect(events.length, 4);
    expect(events[0].phase, ModelRetryPhase.waiting);
    expect(events[0].attempt, 1);
    expect(events[1].phase, ModelRetryPhase.attempting);
    expect(events[1].attempt, 2);
    expect(events[2].phase, ModelRetryPhase.waiting);
    expect(events[3].phase, ModelRetryPhase.attempting);
  });

  test('retries a 503 and succeeds', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) return http.Response('unavailable', 503);
      return http.Response('ok', 200);
    });

    final response = await run(client);

    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('stops after the maximum number of attempts', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('overloaded', 429);
    });

    final response = await run(client, maxAttempts: 3);

    expect(response.statusCode, 429);
    expect(calls, 3);
  });

  test('does not retry a non-retryable status', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('unauthorized', 401);
    });

    final response = await run(client);

    expect(response.statusCode, 401);
    expect(calls, 1);
  });

  test('retries a network failure and then succeeds', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        throw http.ClientException('connection reset', url);
      }
      return http.Response('ok', 200);
    });

    final response = await run(client);

    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('surfaces a network failure after the maximum attempts', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      throw http.ClientException('connection reset', url);
    });

    await expectLater(
      run(client, maxAttempts: 3),
      throwsA(
        isA<ModelProviderException>().having(
          (error) => error.message,
          'message',
          contains('after 3 attempts'),
        ),
      ),
    );
    expect(calls, 3);
  });
}
