import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/engine.dart';
import 'package:harness/core/models/models.dart';
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

class ScriptedModelProvider implements ModelProvider {
  final List<String> script;
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
    if (_index < script.length) {
      return script[_index++];
    }
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
  group('HarnessEngine - Autonomous Multi-Turn Execution Loop', () {
    late CommandRouter router;
    late ContextBuilder contextBuilder;

    setUp(() {
      router = CommandRouter()..registerModule(MockToolModule());
      contextBuilder = ContextBuilder();
    });

    test('coordinates multi-turn tool calling through to final delivery', () async {
      // Script:
      // Turn 1: Emits fetch_data tool call
      // Turn 2: Receives observation and delivers final Markdown message
      final scriptedProvider = ScriptedModelProvider(script: [
        '''
I need to query data first.
<system_call>
{"command": "fetch_data", "parameters": {"id": "1"}}
</system_call>
''',
        '''
<system_call>
{"command": "send_message", "parameters": {"text": "Retrieved data successfully: data_value_42"}}
</system_call>
''',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: scriptedProvider,
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Fetch my data',
        sessionId: 'sess_test_1',
      )) {
        events.add(event);
      }

      // Check event stream sequence
      expect(events[0], isA<EngineTurnStarted>());
      expect(events[1], isA<EngineModelGenerating>());
      expect(events[2], isA<EngineSystemCallStarted>());
      expect(events[3], isA<EngineSystemCallFinished>());
      expect(events[4], isA<EngineModelGenerating>());
      expect(events[5], isA<EngineTurnCompleted>());

      final completedEvent = events.last as EngineTurnCompleted;
      expect(completedEvent.turn.text, 'Retrieved data successfully: data_value_42');
      expect(completedEvent.turn.isAgent, isTrue);
    });

    test('halts and emits error when maxTurns limit is exceeded', () async {
      // Provider that emits tool calls indefinitely
      final infiniteLoopProvider = ScriptedModelProvider(script: [
        '<system_call>{"command": "fetch_data", "parameters": {}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: infiniteLoopProvider,
        maxTurns: 3, // Set low limit for testing
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Infinite task',
        sessionId: 'sess_test_2',
      )) {
        events.add(event);
      }

      final errorEvent = events.last as EngineErrorOccurred;
      expect(errorEvent.message.contains('exceeded maximum turn limit (3 turns)'), isTrue);
    });
  });
}

