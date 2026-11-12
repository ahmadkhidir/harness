import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/platform_actions/platform_actions_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlatformActionGateway gateway;
  late PlatformActionsModule platformModule;

  setUp(() {
    gateway = FakePlatformActionGateway();
    platformModule = PlatformActionsModule(gateway: gateway);
  });

  group('FEAT-007 Acceptance Tests - Native Platform Actions & A2UI Actions', () {
    test(
      'Criterion 1: agent set_alarm system call schedules the native alarm and reports success',
      () async {
        final provider = _RecordingProvider(responses: [
          '<system_call>{"command": "set_alarm", "parameters": {"time": "07:00", "label": "Morning Flight"}}</system_call>',
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Alarm set for 07:00."}}</system_call>',
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

        final completed = events.firstWhere(
          (e) => e is EngineTurnCompleted,
        ) as EngineTurnCompleted;
        expect(completed.turn.text, contains('Alarm set'));
      },
    );

    test(
      'A2UI action goes directly to the model and leaves no user turn in turns.json',
      () async {
        final tempDir =
            await Directory.systemTemp.createTemp('feat007_a2ui_action_');
        addTearDown(() async {
          HarnessFileSystem.instance = null;
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final fileSystem = HarnessFileSystem(rootDir: tempDir);
        fileSystem.ensureBaseDirectoriesSync();
        final database = AppDatabase.inMemory();
        addTearDown(database.close);
        final sessionService = SessionService(
          fileSystem: fileSystem,
          database: database,
        );
        final session = await sessionService.createSession(id: 'sess_action');

        final provider = _RecordingProvider(responses: const [
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "Window seat confirmed."}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(
          engine: engine,
          sessionService: sessionService,
        );
        addTearDown(bloc.close);

        bloc.add(InitializeSessionEvent(sessionId: session.id));
        await bloc.stream.firstWhere((state) => state is HarnessSessionReady);

        final readyFuture = bloc.stream.firstWhere(
          (state) =>
              state is HarnessSessionReady && state.turns.isNotEmpty,
        );

        bloc.add(const HandleA2UIActionEvent(
          surfaceId: 'alarm_surface',
          componentId: 'confirm_button',
          action: 'confirm_choice',
          dataModel: {'choice': 'window', 'seat': '12A'},
        ));

        final ready = await readyFuture as HarnessSessionReady;

        // The click is not a user turn and never enters the chat stream.
        expect(ready.turns.where((turn) => turn.sender == 'user'), isEmpty);
        expect(ready.turns.single.sender, 'agent');
        expect(ready.turns.single.text, 'Window seat confirmed.');

        final persisted = await sessionService.loadTurns(session.id);
        expect(persisted.where((turn) => turn.sender == 'user'), isEmpty);
        expect(persisted.single.sender, 'agent');

        // The click is still the model-facing user event in context.txt.
        final context =
            fileSystem.sessionContextFile(session.id).readAsStringSync();
        expect(
          context,
          contains('USER: The user selected the option "confirm_choice"'),
        );
        expect(context, contains('"seat":"12A"'));

        expect(provider.prompts, isNotEmpty);
        expect(provider.prompts.last, contains('confirm_choice'));
        expect(provider.prompts.last, contains('"seat":"12A"'));

        // No native platform command was executed.
        expect(gateway.alarms, isEmpty);
        expect(gateway.copiedTexts, isEmpty);
      },
    );

    test(
      'platform: is no longer a shortcut; the action is sent to the model',
      () async {
        final provider = _RecordingProvider(responses: const [
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "I will handle that."}}</system_call>',
        ]);
        final engine = HarnessEngine(
          router: CommandRouter(),
          contextBuilder: ContextBuilder(),
          modelProvider: provider,
        );
        final bloc = HarnessSessionBloc(engine: engine);
        addTearDown(bloc.close);

        final readyFuture = bloc.stream.firstWhere(
          (state) =>
              state is HarnessSessionReady && state.turns.isNotEmpty,
        );

        bloc.add(const HandleA2UIActionEvent(
          surfaceId: 'alarm_surface',
          componentId: 'alarm_button',
          action: 'platform:set_alarm',
          dataModel: {'time': '07:00', 'label': 'Morning Flight'},
        ));

        await readyFuture;

        expect(provider.prompts, isNotEmpty);
        expect(provider.prompts.last, contains('platform:set_alarm'));
        expect(provider.prompts.last, contains('"time":"07:00"'));
        expect(gateway.alarms, isEmpty);
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
