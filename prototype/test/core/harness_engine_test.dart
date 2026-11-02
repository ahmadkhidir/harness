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
      expect(completedEvent.turn.toolCalls.length, 1);
      expect(completedEvent.turn.toolCalls.first.call.command, 'fetch_data');
      expect(completedEvent.turn.toolCalls.first.status, 'success');
      expect(completedEvent.turn.toolCalls.first.output, 'data_value_42');
    });

    test('recovers from unclosed system_call tag without leaking raw tags', () async {
      final unclosedProvider = ScriptedModelProvider(script: [
        '<system_call>{"command": "send_message", "parameters": {"text": "### Scene 1: The Gold...',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: unclosedProvider,
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Tell me a scene',
        sessionId: 'sess_unclosed',
      )) {
        events.add(event);
      }

      final completedEvent = events.last as EngineTurnCompleted;
      expect(completedEvent.turn.text, startsWith('### Scene 1: The Gold'));
      expect(completedEvent.turn.text?.contains('<system_call>'), isFalse);
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

    test('self-healing A2UI loop: catches empty or invalid A2UI components and loops back for repair', () async {
      // Turn 1: Model emits invalid A2UI with 0 components
      // Turn 2: Model receives error observation and repairs output with valid components
      final healingProvider = ScriptedModelProvider(script: [
        '''
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Here is the broken card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "main",
          "catalogId": "basic/v1"
        }
      }
    ]
  }
}
</system_call>
''',
        '''
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Here is the corrected card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "main",
          "catalogId": "basic/v1",
          "components": [
            {
              "id": "root",
              "component": "Text",
              "text": "Repaired Card Content"
            }
          ]
        }
      }
    ]
  }
}
</system_call>
''',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: healingProvider,
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Show card',
        sessionId: 'sess_heal',
      )) {
        events.add(event);
      }

      // Verify that engine did NOT stop on the first broken A2UI call!
      expect(healingProvider.recordedCalls.length, 2);
      final secondTurnMessages = healingProvider.recordedCalls[1];
      final systemResponseMsg = secondTurnMessages.last.content;
      expect(systemResponseMsg, contains('<system_response command="send_a2ui" status="error">'));
      expect(systemResponseMsg, contains('No components defined for surface "main"'));

      // Verify turn completed with the repaired A2UI surface
      final completedEvent = events.last as EngineTurnCompleted;
      expect(completedEvent.turn.contentType, equals('a2ui'));
      expect(completedEvent.turn.text, equals('Here is the corrected card:'));
      expect(completedEvent.turn.a2uiSurfaceId, equals('main'));
      expect(completedEvent.turn.toolCalls.first.call.command, equals('send_a2ui'));
      expect(completedEvent.turn.toolCalls.first.status, equals('error'));
    });

    test('injects sliding short-term conversational context (prior turns) into dialogue history', () async {
      final contextProvider = ScriptedModelProvider(script: [
        '<system_call>{"command": "send_message", "parameters": {"text": "Answer referencing previous context"}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: contextProvider,
      );

      final priorTurns = [
        Turn(
          id: 't1',
          sessionId: 'sess_hist',
          timestamp: DateTime.now().toUtc(),
          sender: 'user',
          contentType: 'text',
          text: 'What is the capital of France?',
        ),
        Turn(
          id: 't2',
          sessionId: 'sess_hist',
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: 'The capital of France is Paris.',
        ),
      ];

      await for (final _ in engine.executeTurn(
        userPrompt: 'What is its population?',
        sessionId: 'sess_hist',
        recentHistory: priorTurns,
      )) {}

      expect(contextProvider.recordedCalls.isNotEmpty, isTrue);
      final messagesSent = contextProvider.recordedCalls.first;

      // Messages should contain:
      // 1. user: What is the capital of France?
      // 2. assistant: The capital of France is Paris.
      // 3. user: What is its population?
      expect(messagesSent.length, 3);
      expect(messagesSent[0].role, equals('user'));
      expect(messagesSent[0].content, equals('What is the capital of France?'));
      expect(messagesSent[1].role, equals('assistant'));
      expect(messagesSent[1].content, equals('The capital of France is Paris.'));
      expect(messagesSent[2].role, equals('user'));
      expect(messagesSent[2].content, equals('What is its population?'));
    });
  });
}

