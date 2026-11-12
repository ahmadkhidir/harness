import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/modules/base/harness_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

int activeCalls = 0;
int maxConcurrentCalls = 0;

void _trackCallStart() {
  activeCalls++;
  if (activeCalls > maxConcurrentCalls) {
    maxConcurrentCalls = activeCalls;
  }
}

void _trackCallEnd() {
  activeCalls--;
}

class TestStorageModule extends HarnessModule {
  int executionCount = 0;

  @override
  String get moduleName => 'storage';

  @override
  List<CommandDefinition> get commands => [
    CommandDefinition(
      command: 'read_file',
      description: 'Reads file content',
      parametersSchema: const {'type': 'object'},
    ),
  ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    executionCount++;
    _trackCallStart();
    await Future.delayed(const Duration(milliseconds: 50));
    _trackCallEnd();
    return SystemResponse.success(
      command: command,
      data: 'Document content ABC',
    );
  }
}

class TestWebModule extends HarnessModule {
  int executionCount = 0;

  @override
  String get moduleName => 'web';

  @override
  List<CommandDefinition> get commands => [
    CommandDefinition(
      command: 'web_search',
      description: 'Searches the web',
      parametersSchema: const {'type': 'object'},
    ),
  ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    executionCount++;
    _trackCallStart();
    await Future.delayed(const Duration(milliseconds: 50));
    _trackCallEnd();
    return SystemResponse.success(
      command: command,
      data: [
        {'title': 'Flutter News', 'url': 'https://flutter.dev'},
      ],
    );
  }
}

class TestCrashingModule extends HarnessModule {
  @override
  String get moduleName => 'crashing';

  @override
  List<CommandDefinition> get commands => [
    CommandDefinition(
      command: 'crash_op',
      description: 'Always throws',
      parametersSchema: const {'type': 'object'},
    ),
  ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    throw Exception('Intentional module failure for edge case testing');
  }
}

class ScriptedModelProvider extends ModelProvider {
  final List<String> script;
  final List<List<ModelMessage>> receivedHistories = [];
  int _step = 0;

  ScriptedModelProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
    id: 'test_provider',
    providerType: 'local_device',
    displayName: 'Test LLM',
    modelName: 'test-llm-1',
  );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    receivedHistories.add(List.from(messages));
    if (_step < script.length) {
      return script[_step++];
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
  group('FEAT-001 Acceptance Tests - Multi-Turn Loop & Parallel Command Router', () {
    late CommandRouter router;
    late ContextBuilder contextBuilder;
    late TestStorageModule storageModule;
    late TestWebModule webModule;
    late TestCrashingModule crashingModule;

    setUp(() {
      activeCalls = 0;
      maxConcurrentCalls = 0;
      router = CommandRouter();
      contextBuilder = ContextBuilder();
      storageModule = TestStorageModule();
      webModule = TestWebModule();
      crashingModule = TestCrashingModule();

      router.registerModule(storageModule);
      router.registerModule(webModule);
      router.registerModule(crashingModule);
    });

    test(
      'Criterion 1: Executes multiple system calls in parallel via Future.wait',
      () async {
        final model = ScriptedModelProvider([
          // Turn 1: Emits two parallel system calls
          '''
Scratchpad: Need to inspect both local storage and the live web.
<system_call>
{"command": "read_file", "parameters": {"path": "doc.txt"}}
</system_call>
<system_call>
{"command": "web_search", "parameters": {"query": "Flutter 2026"}}
</system_call>
''',
          // Turn 2: Delivery after observations
          '''
<system_call>
{"command": "send_ui_message", "parameters": {"message": "Compiled findings from storage and web."}}
</system_call>
''',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: contextBuilder,
          modelProvider: model,
        );

        final events = await engine
            .executeTurn(
              userPrompt: 'Analyze doc and search updates',
              sessionId: 'sess_feat_1',
            )
            .toList();

        // Parallel execution: both calls ran concurrently at peak
        expect(storageModule.executionCount, 1);
        expect(webModule.executionCount, 1);
        expect(maxConcurrentCalls, 2);

        final completed = events.whereType<EngineTurnCompleted>().first;
        expect(completed.turn.text, 'Compiled findings from storage and web.');
      },
    );

    test(
      'Criterion 2: Dispatches progressive events to HarnessSessionBloc to update tool indicators in real time',
      () async {
        final model = ScriptedModelProvider([
          '''
<system_call>{"command": "read_file", "parameters": {"path": "test.txt"}}</system_call>
<system_call>{"command": "web_search", "parameters": {"query": "Harness"}}</system_call>
''',
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Done."}}</system_call>',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: contextBuilder,
          modelProvider: model,
        );

        final bloc = HarnessSessionBloc(engine: engine);
        final states = <HarnessSessionState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeSessionEvent(sessionId: 'sess_bloc_1'));
        await pumpEventQueue();

        final finished = bloc.stream
            .firstWhere(
              (state) =>
                  state is HarnessSessionReady && state.turns.length == 2,
            )
            .timeout(const Duration(seconds: 10));

        bloc.add(const SubmitUserPromptEvent('Run parallel actions'));

        final finalState = await finished;

        // Verify states progressed through turn execution with real-time tool indicators
        final executingStates = states
            .whereType<HarnessTurnExecuting>()
            .toList();
        expect(executingStates.isNotEmpty, isTrue);

        // Verify indicators were registered for both calls
        final hasToolIndicators = executingStates.any(
          (s) => s.toolIndicators.any((ind) => ind.call.command == 'read_file'),
        );
        expect(hasToolIndicators, isTrue);

        // Final state must be ready with completed turns
        expect(finalState, isA<HarnessSessionReady>());
        expect(finalState.turns.length, 2); // user turn + agent turn
        expect(finalState.turns.last.text, 'Done.');

        await sub.cancel();
        await bloc.close();
      },
    );

    test(
      'Criterion 3: Wraps observations into <system_response> blocks until final delivery command',
      () async {
        final model = ScriptedModelProvider([
          '<system_call>{"command": "read_file", "parameters": {"path": "notes.txt"}}</system_call>',
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Final response after reading"}}</system_call>',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: contextBuilder,
          modelProvider: model,
        );

        await engine
            .executeTurn(userPrompt: 'Read notes', sessionId: 'sess_feat_1_obs')
            .toList();

        expect(model.receivedHistories.length, 2);

        // Verify second turn history contains the observation wrapped in <system_response>
        final secondTurnMessages = model.receivedHistories[1];
        final lastObservationMessage = secondTurnMessages.last.content;
        expect(
          lastObservationMessage.contains(
            '<system_response command="read_file" status="success">',
          ),
          isTrue,
        );
        expect(lastObservationMessage.contains('Document content ABC'), isTrue);
      },
    );

    test(
      'Edge Case 1: Exception in one call returns error observation while siblings succeed',
      () async {
        final model = ScriptedModelProvider([
          '''
<system_call>{"command": "crash_op", "parameters": {}}</system_call>
<system_call>{"command": "read_file", "parameters": {"path": "ok.txt"}}</system_call>
''',
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Handled crash gracefully"}}</system_call>',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: contextBuilder,
          modelProvider: model,
        );

        final events = await engine
            .executeTurn(
              userPrompt: 'Test crash handling',
              sessionId: 'sess_crash_1',
            )
            .toList();

        final finishedEvents = events
            .whereType<EngineSystemCallFinished>()
            .toList();
        expect(finishedEvents.length, 2);

        final crashResponse = finishedEvents
            .firstWhere((e) => e.call.command == 'crash_op')
            .response;
        expect(crashResponse.isError, isTrue);
        expect(
          crashResponse.errorMessage?.contains('Intentional module failure'),
          isTrue,
        );

        final okResponse = finishedEvents
            .firstWhere((e) => e.call.command == 'read_file')
            .response;
        expect(okResponse.isSuccess, isTrue);

        final completed = events.whereType<EngineTurnCompleted>().first;
        expect(completed.turn.text, 'Handled crash gracefully');
      },
    );

    test('Edge Case 2: Halts when hard turn limit is exceeded', () async {
      final loopingModel = ScriptedModelProvider([
        '<system_call>{"command": "read_file", "parameters": {}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: loopingModel,
        maxTurns: 4,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Loop forever', sessionId: 'sess_loop_1')
          .toList();

      expect(events.last, isA<EngineErrorOccurred>());
      final err = events.last as EngineErrorOccurred;
      expect(
        err.message.contains('exceeded maximum turn limit (4 turns)'),
        isTrue,
      );
    });

    test(
      'Fallback: Returns structured error observation on malformed JSON or unregistered command',
      () async {
        final model = ScriptedModelProvider([
          // Model emits malformed JSON inside system_call
          '''
<system_call>
{ command: "unregistered", invalid_json }
</system_call>
''',
          // Model corrects itself on next turn
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Self-corrected after error observation"}}</system_call>',
        ]);

        final engine = HarnessEngine(
          router: router,
          contextBuilder: contextBuilder,
          modelProvider: model,
        );

        final events = await engine
            .executeTurn(
              userPrompt: 'Trigger parse error',
              sessionId: 'sess_fallback_1',
            )
            .toList();

        final finishedEvents = events
            .whereType<EngineSystemCallFinished>()
            .toList();
        expect(finishedEvents.first.response.isError, isTrue);

        // Verify the observation fed back to the model contained the error observation
        final secondTurnMessages = model.receivedHistories[1];
        expect(
          secondTurnMessages.last.content.contains(
            'Invalid command or malformed JSON',
          ),
          isTrue,
        );

        final completed = events.whereType<EngineTurnCompleted>().first;
        expect(completed.turn.text, 'Self-corrected after error observation');
      },
    );
  });
}
