import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/modules/runner/runner_module.dart';
import 'package:harness/modules/runner/runner_provider.dart';
import 'package:harness/modules/web/web_module.dart';
import 'package:harness/modules/web/web_providers.dart';
import 'package:harness/providers/model_provider.dart';

import '../../mocks/fake_bridges.dart';

/// Scripted provider that returns responses in order and records prompts.
class _ScriptedProvider extends ModelProvider {
  final List<String> script;
  final List<String> prompts = [];
  int _index = 0;

  _ScriptedProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted_bridge',
        providerType: 'gemini',
        displayName: 'Scripted Bridge Model',
        modelName: 'scripted-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    if (messages.isNotEmpty) prompts.add(messages.last.content);
    if (_index < script.length) return script[_index++];
    return script.last;
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FEAT-008 Acceptance Tests - External Runner & Web Bridges', () {
    test(
      'Criterion 1: web_search returns a structured list of titles, URLs, and snippets',
      () async {
        final search = FakeWebSearchProvider(results: const [
          WebSearchResult(
            title: 'Flutter 3.x release notes',
            url: 'https://flutter.dev/releases',
            snippet: 'Stable channel notes.',
          ),
          WebSearchResult(
            title: 'Dart release notes',
            url: 'https://dart.dev/releases',
            snippet: 'Dart SDK notes.',
          ),
        ]);

        final router = CommandRouter()
          ..registerModule(WebModule(
            searchProviderFactory: () async => search,
            fetchProvider: FakeWebFetchProvider(),
          ));

        final provider = _ScriptedProvider([
          '<system_call>{"command": "web_search", "parameters": {"query": "Flutter 3.x release notes", "maxResults": 2}}</system_call>',
          '<system_call>{"command": "send_message", "parameters": {"text": "Found two sources."}}</system_call>',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );

        final events = await engine
            .executeTurn(
              userPrompt: 'Look up the Flutter 3.x release notes.',
              sessionId: 'sess_web_search',
            )
            .toList();

        final finished = events.firstWhere(
          (event) =>
              event is EngineSystemCallFinished &&
              event.call.command == 'web_search',
        ) as EngineSystemCallFinished;

        expect(finished.response.isSuccess, isTrue);
        final data = finished.response.data as Map<String, dynamic>;
        final results = data['results'] as List;
        expect(results, hasLength(2));
        expect(results.first, containsPair('title', 'Flutter 3.x release notes'));
        expect(results.first, containsPair('url', 'https://flutter.dev/releases'));
        expect(results.first, containsPair('snippet', 'Stable channel notes.'));

        final completed =
            events.firstWhere((event) => event is EngineTurnCompleted)
                as EngineTurnCompleted;
        expect(completed.turn.text, 'Found two sources.');
      },
    );

    test('Criterion 2: web_fetch returns readable Markdown from the provider',
        () async {
      final fetch = FakeWebFetchProvider(
        result: const WebFetchResult(
          url: 'https://example.com/article',
          markdown: '# Article\n\nClean body text.',
          truncated: false,
        ),
      );

      final router = CommandRouter()
        ..registerModule(WebModule(
          searchProviderFactory: () async => FakeWebSearchProvider(),
          fetchProvider: fetch,
        ));

      final provider = _ScriptedProvider([
        '<system_call>{"command": "web_fetch", "parameters": {"url": "https://example.com/article"}}</system_call>',
        '<system_call>{"command": "send_message", "parameters": {"text": "Read the page."}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(
            userPrompt: 'Read that page for me.',
            sessionId: 'sess_web_fetch',
          )
          .toList();

      final finished = events.firstWhere(
        (event) =>
            event is EngineSystemCallFinished &&
            event.call.command == 'web_fetch',
      ) as EngineSystemCallFinished;

      expect(finished.response.isSuccess, isTrue);
      final data = finished.response.data as Map<String, dynamic>;
      expect(data['markdown'], contains('# Article'));
      expect(data['truncated'], isFalse);
    });

    test('Criterion 3: execute_script returns stdout and stderr from the runner',
        () async {
      final runner = FakeRunnerProvider(
        result: const ScriptExecutionResult(
          exitCode: 0,
          stdout: '1267650600228229401496703205376',
          stderr: '',
          executionTimeMs: 12,
        ),
      );

      final router = CommandRouter()
        ..registerModule(
          RunnerModule(runnerProviderFactory: () async => runner),
        );

      final provider = _ScriptedProvider([
        '<system_call>{"command": "execute_script", "parameters": {"language": "python", "code": "print(2**100)", "timeoutSeconds": 10}}</system_call>',
        '<system_call>{"command": "send_message", "parameters": {"text": "Computed the value."}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(
            userPrompt: 'Compute two to the power of one hundred.',
            sessionId: 'sess_script',
          )
          .toList();

      final finished = events.firstWhere(
        (event) =>
            event is EngineSystemCallFinished &&
            event.call.command == 'execute_script',
      ) as EngineSystemCallFinished;

      expect(finished.response.isSuccess, isTrue);
      final data = finished.response.data as Map<String, dynamic>;
      expect(data['exitCode'], 0);
      expect(data['stdout'], '1267650600228229401496703205376');
      expect(data['stderr'], '');
      expect(runner.lastLanguage, 'python');
      expect(runner.lastTimeoutSeconds, 10);
    });

    test('Edge Case: unconfigured runner returns an informative observation',
        () async {
      final module = RunnerModule(runnerProviderFactory: () async => null);

      final response = await module.executeCommand('execute_script', {
        'language': 'bash',
        'code': 'echo hi',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Add a runner endpoint in Settings'));
    });

    test('Edge Case: scraping block surfaces the HTTP status', () async {
      final module = WebModule(
        searchProviderFactory: () async => FakeWebSearchProvider(),
        fetchProvider: FakeWebFetchProvider(
          error: const WebBridgeException(
            'HTTP 403 fetching https://example.com/blocked.',
            statusCode: 403,
          ),
        ),
      );

      final response = await module.executeCommand('web_fetch', {
        'url': 'https://example.com/blocked',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('403'));
    });
  });
}
