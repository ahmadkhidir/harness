import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/models/scheduled_timer.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/data/services/timer_service.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

class _ReplyProvider extends ModelProvider {
  @override
  ProviderConfig get config => ProviderConfig(
        id: 'timer_reply',
        providerType: 'gemini',
        displayName: 'Timer Reply',
        modelName: 'timer-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    return '<system_call>{"command": "send_message", "parameters": {"text": "How did it go?"}}</system_call>';
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
  test('a timer prompt runs without adding a user turn', () async {
    final tempDir = await Directory.systemTemp.createTemp('harness_timer_bloc_');
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
    final session = await sessionService.createSession(title: 'Timer Bloc');
    final timer = ScheduledTimer(
      id: 'timer_test',
      sessionId: session.id,
      prompt: 'Ask how the exercise went',
      createdAt: DateTime.now().toUtc(),
      firesAt: DateTime.now().toUtc(),
      status: ScheduledTimerStatus.queued,
    );
    await sessionService.upsertTimer(session.id, timer);

    final timerService = TimerService(sessionService: sessionService);
    addTearDown(timerService.dispose);

    final engine = HarnessEngine(
      router: CommandRouter(),
      contextBuilder: ContextBuilder(),
      modelProvider: _ReplyProvider(),
    );
    final bloc = HarnessSessionBloc(
      engine: engine,
      sessionService: sessionService,
      timerService: timerService,
    );
    addTearDown(bloc.close);

    final switched = bloc.stream.firstWhere(
      (state) => state is HarnessSessionReady && state.sessionId == session.id,
    );
    bloc.add(SwitchSessionEvent(session.id));
    await switched;

    final readyFuture = bloc.stream.firstWhere(
      (state) => state is HarnessSessionReady && state.turns.isNotEmpty,
    );
    bloc.add(RunScheduledTimerEvent(timer));
    final ready = await readyFuture as HarnessSessionReady;

    // The agent reply is a normal turn; the timer prompt is not.
    expect(ready.turns, hasLength(1));
    expect(ready.turns.single.sender, 'agent');
    expect(ready.turns.single.text, 'How did it go?');

    final context = fileSystem
        .sessionContextFile(session.id)
        .readAsStringSync();
    expect(context, contains('USER: Ask how the exercise went'));
    expect(context, contains('AGENT: How did it go?'));

    final stored = (await sessionService.loadTimers(session.id)).single;
    expect(stored.status, ScheduledTimerStatus.completed);
    expect(stored.firedAt, isNotNull);
  });
}
