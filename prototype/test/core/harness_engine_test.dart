import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/modules/a2ui/a2ui_surface_store.dart';
import 'package:harness/modules/base/harness_module.dart';
import 'package:harness/providers/model_provider.dart';

class MockToolModule extends HarnessModule {
  @override
  String get moduleName => 'tools';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'fetch_data',
          description: 'Fetches mock data',
          parametersSchema: const {'type': 'object'},
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    return SystemResponse.success(command: command, data: 'data_value_42');
  }
}

class ScriptedModelProvider extends ModelProvider {
  final List<String> script;
  final List<List<ModelMessage>> recordedCalls = [];
  int _index = 0;

  ScriptedModelProvider({required this.script});

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted',
        providerType: 'local_device',
        displayName: 'Scripted Mock',
        modelName: 'scripted-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    recordedCalls.add(List.from(messages));
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
  late CommandRouter router;
  late ContextBuilder contextBuilder;

  setUp(() {
    router = CommandRouter()..registerModule(MockToolModule());
    contextBuilder = ContextBuilder();
  });

  group('HarnessEngine - Autonomous Multi-Turn Execution Loop', () {
    test('coordinates a tool loop through to final text delivery', () async {
      final provider = ScriptedModelProvider(script: [
        '<system_call>{"command": "fetch_data", "parameters": {"id": "1"}}</system_call>',
        '<system_call>{"command": "send_ui_message", "parameters": {"message": "Retrieved data successfully: data_value_42"}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Fetch my data', sessionId: 'sess_test_1')
          .toList();

      expect(events[0], isA<EngineTurnStarted>());
      expect(events[1], isA<EngineModelGenerating>());
      expect(events[2], isA<EngineSystemCallStarted>());
      expect(events[3], isA<EngineSystemCallFinished>());

      final completed = events.last as EngineTurnCompleted;
      expect(completed.turn.text, 'Retrieved data successfully: data_value_42');
      expect(completed.turn.toolCalls.length, 1);
      expect(completed.turn.toolCalls.first.call.command, 'fetch_data');
      expect(completed.turn.toolCalls.first.status, 'success');
    });

    test('recovers from an unclosed delivery without leaking tags', () async {
      final provider = ScriptedModelProvider(script: [
        '<system_call>{"command": "send_ui_message", "parameters": {"message": "### Scene 1: The Gold...',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Tell me a scene', sessionId: 'sess_unclosed')
          .toList();

      final completed = events.last as EngineTurnCompleted;
      expect(completed.turn.text, startsWith('### Scene 1: The Gold'));
      expect(completed.turn.text, isNot(contains('<system_call>')));
    });

    test('halts when the maximum turn limit is exceeded', () async {
      final provider = ScriptedModelProvider(script: [
        '<system_call>{"command": "fetch_data", "parameters": {}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
        maxTurns: 3,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Infinite task', sessionId: 'sess_test_2')
          .toList();

      final error = events.last as EngineErrorOccurred;
      expect(error.message, contains('exceeded maximum turn limit (3 turns)'));
    });

    test('repairs an invalid A2UI surface and completes', () async {
      final provider = ScriptedModelProvider(script: [
        '<system_call>{"command": "send_ui_message", "parameters": {"message": {"a2ui": ['
            '{"version": "1.0", "createSurface": {"surfaceId": "main", "catalogId": "basic/v1", "components": [{"id": "root", "component": "Card"}]}}'
            ']}}}</system_call>',
        '<system_call>{"command": "send_ui_message", "parameters": {"message": {"a2ui": ['
            '{"version": "1.0", "createSurface": {"surfaceId": "main", "catalogId": "basic/v1"}},'
            '{"version": "1.0", "updateComponents": {"surfaceId": "main", "components": [{"id": "root", "component": "Card", "child": "title"}, {"id": "title", "component": "Text", "text": "Fixed"}]}}'
            ']}}}</system_call>',
      ]);

      final store = A2UISurfaceStore();
      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(
            userPrompt: 'Show card',
            sessionId: 'sess_heal',
            surfaceStore: store,
          )
          .toList();

      expect(provider.recordedCalls.length, 2);
      expect(
        provider.recordedCalls[1].last.content,
        contains('system_response command="send_ui_message"'),
      );

      final completed = events.last as EngineTurnCompleted;
      expect(completed.turn.contentType, 'a2ui');
      expect(completed.turn.text, isNull);
      expect(completed.turn.a2uiSurfaceId, 'main');
      expect(store.surface('main')!.components['title']!['text'], 'Fixed');
    });

    test('injects the transcript and current request as one user message',
        () async {
      final provider = ScriptedModelProvider(script: [
        '<system_call>{"command": "send_ui_message", "parameters": {"message": "Answer"}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      const transcript = 'USER: What is the capital of France?\n'
          'AGENT: The capital of France is Paris.';

      await engine
          .executeTurn(
            userPrompt: 'What is its population?',
            sessionId: 'sess_hist',
            sessionTranscript: transcript,
          )
          .toList();

      final messages = provider.recordedCalls.first;
      expect(messages.length, 1);
      expect(messages.single.role, 'user');
      expect(messages.single.content, contains('<session_transcript>'));
      expect(messages.single.content, contains('<current_request>'));
    });

    test('retries once when the model returns an empty response', () async {
      final provider = ScriptedModelProvider(script: [
        '',
        '<system_call>{"command": "send_ui_message", "parameters": {"message": "Hello! How can I help?"}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Hello', sessionId: 'sess_empty_retry')
          .toList();

      expect(provider.recordedCalls.length, 2);
      expect(
        provider.recordedCalls[1].last.content,
        contains('send_ui_message'),
      );
      final completed = events.last as EngineTurnCompleted;
      expect(completed.turn.text, 'Hello! How can I help?');
    });

    test('reports an error instead of a blank turn after repeated empty replies',
        () async {
      final provider = ScriptedModelProvider(script: ['', '   ']);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Hello', sessionId: 'sess_empty_error')
          .toList();

      expect(events.whereType<EngineTurnCompleted>(), isEmpty);
      final error = events.whereType<EngineErrorOccurred>().single;
      expect(error.message, contains('empty response'));
    });
  });
}
