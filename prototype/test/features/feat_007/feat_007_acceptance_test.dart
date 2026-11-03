import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/platform_actions/a2ui_event_router.dart';
import 'package:harness/modules/platform_actions/platform_actions_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/presentation/widgets/message_bubble.dart';
import 'package:harness/providers/model_provider.dart';

import '../../mocks/fake_platform_action_gateway.dart';

/// Scripted provider that records every prompt sent to the model.
class _RecordingProvider extends ModelProvider {
  final List<String> responses;
  final List<String> prompts = [];
  int _index = 0;

  _RecordingProvider({required this.responses});

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted_platform',
        providerType: 'gemini',
        displayName: 'Scripted Platform Model',
        modelName: 'scripted-1',
        isActive: true,
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    if (messages.isNotEmpty) {
      prompts.add(messages.last.content);
    }
    if (_index < responses.length) {
      return responses[_index++];
    }
    return responses.last;
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

Turn _a2uiTurn(String action, {Map<String, dynamic>? parameters}) {
  return Turn(
    id: 'turn_alarm_card',
    sessionId: 'sess_1',
    timestamp: DateTime.now().toUtc(),
    sender: 'agent',
    contentType: 'a2ui',
    a2uiSurfaceId: 'alarm_surface',
    a2uiPayload: {
      'messages': [
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'alarm_surface',
            'catalogId': 'basic/v1',
          },
        },
        {
          'version': '1.0',
          'updateDataModel': {
            'surfaceId': 'alarm_surface',
            'value': {'time': '07:00', 'label': 'Morning Flight'},
          },
        },
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'alarm_surface',
            'components': [
              {
                'id': 'root',
                'type': 'Card',
                'properties': {'child': 'action_button'},
              },
              {
                'id': 'action_button',
                'type': 'Button',
                'properties': {
                  'label': 'Set Alarm',
                  'action': action,
                  'parameters': ?parameters,
                },
              },
            ],
          },
        },
      ],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlatformActionGateway gateway;
  late PlatformActionsModule platformModule;
  late A2UIEventRouter eventRouter;

  setUp(() {
    gateway = FakePlatformActionGateway();
    platformModule = PlatformActionsModule(gateway: gateway);
    eventRouter = A2UIEventRouter(platformActions: platformModule);
  });

  group('FEAT-007 Acceptance Tests - Native Platform Actions & A2UI Event Routing', () {
    test(
      'Criterion 1: agent set_alarm system call schedules the native alarm and reports success',
      () async {
        final provider = _RecordingProvider(responses: [
          '<system_call>{"command": "set_alarm", "parameters": {"time": "07:00", "label": "Morning Flight"}}</system_call>',
          '<system_call>{"command": "send_message", "parameters": {"text": "Alarm set for 07:00."}}</system_call>',
        ]);

        final router = CommandRouter()..registerModule(platformModule);
        final engine = HarnessEngine(
          router: router,
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );

        final events = await engine
            .executeTurn(
              userPrompt: 'Wake me up at seven for my flight.',
              sessionId: 'sess_1',
            )
            .toList();

        final finished = events.firstWhere(
          (e) => e is EngineSystemCallFinished && e.call.command == 'set_alarm',
        ) as EngineSystemCallFinished;

        expect(finished.response.isSuccess, isTrue);
        expect(
          finished.response.data,
          equals({'status': 'success', 'action': 'set_alarm'}),
        );
        expect(gateway.alarms, hasLength(1));
        expect(gateway.alarms.single['time'], equals('07:00'));
        expect(gateway.alarms.single['label'], equals('Morning Flight'));

        final completed =
            events.firstWhere((e) => e is EngineTurnCompleted) as EngineTurnCompleted;
        expect(completed.turn.text, contains('Alarm set'));
      },
    );

    testWidgets(
      'Criterion 2: tapping a platform A2UI button executes the action without an LLM turn',
      (tester) async {
        final provider = _RecordingProvider(responses: [
          '<system_call>{"command": "send_message", "parameters": {"text": "unused"}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          a2uiEventRouter: eventRouter,
        );
        addTearDown(bloc.close);

        final resolvedFuture = bloc.stream
            .firstWhere((state) => state is HarnessA2UIActionResolved);

        await tester.pumpWidget(
          BlocProvider<HarnessSessionBloc>.value(
            value: bloc,
            child: MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  turn: _a2uiTurn('platform:set_alarm'),
                  onA2UIAction: (action, dataModel) {
                    bloc.add(HandleA2UIActionEvent(
                      action: action,
                      dataModel: dataModel,
                    ));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Set Alarm'));
        await tester.pumpAndSettle();

        final resolved = await resolvedFuture as HarnessA2UIActionResolved;
        expect(resolved.isError, isFalse);
        expect(resolved.message, contains('Alarm scheduled'));

        // Native execution happened exactly once, and no model turn was started.
        expect(gateway.alarms, hasLength(1));
        expect(gateway.alarms.single['time'], equals('07:00'));
        expect(gateway.alarms.single['label'], equals('Morning Flight'));
        expect(provider.prompts, isEmpty);
      },
    );

    testWidgets(
      'Criterion 2b: inline button parameters override the surface data model',
      (tester) async {
        final provider = _RecordingProvider(responses: const [
          '<system_call>{"command": "send_message", "parameters": {"text": "unused"}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          a2uiEventRouter: eventRouter,
        );
        addTearDown(bloc.close);

        final resolvedFuture = bloc.stream
            .firstWhere((state) => state is HarnessA2UIActionResolved);

        await tester.pumpWidget(
          BlocProvider<HarnessSessionBloc>.value(
            value: bloc,
            child: MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  turn: _a2uiTurn(
                    'platform:set_alarm',
                    parameters: {'time': '09:15', 'label': 'Breakfast'},
                  ),
                  onA2UIAction: (action, dataModel) {
                    bloc.add(HandleA2UIActionEvent(
                      action: action,
                      dataModel: dataModel,
                    ));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Set Alarm'));
        await tester.pumpAndSettle();
        await resolvedFuture;

        expect(gateway.alarms.single['time'], equals('09:15'));
        expect(gateway.alarms.single['label'], equals('Breakfast'));
      },
    );

    test(
      'Edge Case: a platform action during an active turn preserves execution state',
      () async {
        final provider = _RecordingProvider(responses: const [
          '<system_call>{"command": "send_message", "parameters": {"text": "unused"}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          a2uiEventRouter: eventRouter,
        );
        addTearDown(bloc.close);

        final executingFuture = bloc.stream.firstWhere(
          (state) => state is HarnessTurnExecuting,
        );
        bloc.add(SessionEngineProgressReceived(
          EngineSystemCallStarted(
            SystemCall(command: 'grep', parameters: const {'pattern': 'TODO'}),
          ),
        ));
        await executingFuture;

        final noticeFuture = bloc.stream.firstWhere(
          (state) => state is HarnessA2UIActionResolved,
        );
        bloc.add(const HandleA2UIActionEvent(
          action: 'platform:set_alarm',
          dataModel: {'time': '07:00', 'label': 'Morning Flight'},
        ));

        final notice = await noticeFuture as HarnessA2UIActionResolved;
        expect(notice.isError, isFalse);
        expect(gateway.alarms, hasLength(1));

        // The transient notice must not clobber an in-flight turn, otherwise
        // tool indicators and the stop control would disappear mid-execution.
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state, isA<HarnessTurnExecuting>());
        expect(
          (bloc.state as HarnessTurnExecuting).toolIndicators.single.call.command,
          equals('grep'),
        );
      },
    );

    test(
      'Criterion 3: tapping a conversation action dispatches a new turn with the button payload',
      () async {
        final provider = _RecordingProvider(responses: [
          '<system_call>{"command": "send_message", "parameters": {"text": "Window seat confirmed."}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          a2uiEventRouter: eventRouter,
        );
        addTearDown(bloc.close);

        final readyFuture = bloc.stream.firstWhere(
          (state) =>
              state is HarnessSessionReady && state.turns.isNotEmpty,
        );

        bloc.add(const HandleA2UIActionEvent(
          action: 'confirm_choice',
          dataModel: {'choice': 'window', 'seat': '12A'},
        ));

        final ready = await readyFuture as HarnessSessionReady;

        // Interface selections are sent to the model but are not rendered as
        // user chat turns.
        expect(ready.turns.any((turn) => turn.sender == 'user'), isFalse);
        expect(ready.turns.single.sender, equals('agent'));
        expect(ready.turns.single.text, equals('Window seat confirmed.'));
        expect(provider.prompts, isNotEmpty);
        expect(provider.prompts.last, contains('confirm_choice'));
        expect(provider.prompts.last, contains('"seat":"12A"'));
        // Platform gateway was never invoked for a conversational action.
        expect(gateway.alarms, isEmpty);
        expect(gateway.copiedTexts, isEmpty);
      },
    );

    test(
      'A2UI conversation action is written to context.txt but not turns.json',
      () async {
        final tempDir =
            await Directory.systemTemp.createTemp('feat007_hidden_action_');
        addTearDown(() async {
          HarnessFileSystem.instance = null;
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final fileSystem = HarnessFileSystem(rootDir: tempDir);
        fileSystem.ensureBaseDirectoriesSync();
        final sessionService = SessionService(
          fileSystem: fileSystem,
          database: AppDatabase.inMemory(),
        );

        final provider = _RecordingProvider(responses: const [
          '<system_call>{"command": "send_message", "parameters": {"text": "Resume tailored."}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          a2uiEventRouter: eventRouter,
          sessionService: sessionService,
        );
        addTearDown(bloc.close);

        final readyFuture = bloc.stream.firstWhere(
          (state) => state is HarnessSessionReady && state.turns.isNotEmpty,
        );

        bloc.add(const HandleA2UIActionEvent(
          action: 'view_tailored_resume',
          dataModel: {
            'job': {'title': 'Senior Backend Engineer', 'location': 'Nigeria'},
          },
        ));

        final ready = await readyFuture as HarnessSessionReady;
        final sessionId = ready.sessionId!;

        final context = fileSystem.sessionContextFile(sessionId).readAsStringSync();
        expect(
          context,
          contains('USER: The user selected the option "view_tailored_resume"'),
        );
        expect(context, contains('"location":"Nigeria"'));

        final persisted = await sessionService.loadTurns(sessionId);
        expect(persisted.any((turn) => turn.sender == 'user'), isFalse);
        expect(persisted.single.sender, 'agent');
      },
    );

    test(
      'Edge Case: denied alarm permission returns an informative observation',
      () async {
        gateway.denyAlarmPermission = true;

        final response = await platformModule.executeCommand('set_alarm', {
          'time': '07:00',
          'label': 'Morning Flight',
        });

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('Permission denied for alarms'));
        expect(gateway.alarms, isEmpty);
      },
    );

    test(
      'Edge Case: invalid time format is rejected before invoking native channels',
      () async {
        final response = await platformModule.executeCommand('set_alarm', {
          'time': '7 PM',
          'label': 'Morning Flight',
        });

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('Invalid time format'));
        expect(gateway.alarms, isEmpty);
      },
    );
  });
}
