import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

class _NoopProvider extends ModelProvider {
  @override
  ProviderConfig get config => ProviderConfig(
        id: 'noop',
        providerType: 'gemini',
        displayName: 'Noop',
        modelName: 'noop',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    return '';
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {}
}

void main() {
  test('session load replays A2UI turns into live surfaces', () async {
    final tempDir = await Directory.systemTemp.createTemp('harness_surfaces_');
    addTearDown(() async {
      HarnessFileSystem.instance = null;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final fs = HarnessFileSystem(rootDir: tempDir);
    fs.ensureBaseDirectoriesSync();
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    final sessionService = SessionService(database: db, fileSystem: fs);
    final session = await sessionService.createSession(id: 'sess_surface');

    await sessionService.appendTurn(
      session.id,
      Turn(
        id: 'turn_surface',
        sessionId: session.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'a2ui',
        a2uiSurfaceId: 'main',
        a2uiPayload: const {
          'messages': [
            {
              'version': '1.0',
              'createSurface': {
                'surfaceId': 'main',
                'catalogId': 'basic/v1',
                'components': [
                  {'id': 'root', 'component': 'Text', 'text': 'Hello'},
                ],
              },
            },
          ],
        },
      ),
    );

    final engine = HarnessEngine(
      router: CommandRouter(),
      contextBuilder: ContextBuilder(),
      modelProvider: _NoopProvider(),
    );
    final bloc = HarnessSessionBloc(
      engine: engine,
      sessionService: sessionService,
    );
    addTearDown(bloc.close);

    bloc.add(InitializeSessionEvent(sessionId: session.id));
    final state = await bloc.stream
        .firstWhere((state) => state is HarnessSessionReady)
        as HarnessSessionReady;

    expect(state.surfaces['main'], isNotNull);
    expect(state.surfaces['main']!.components['root']!['text'], 'Hello');

    // A local component value change updates the live surface data model
    // without creating a turn or a model request.
    bloc.add(const UpdateA2UISurfaceDataEvent(
      surfaceId: 'main',
      path: '/status',
      value: 'ready',
    ));
    final updated = await bloc.stream.firstWhere(
      (state) => state.surfaces['main']?.dataModel['status'] == 'ready',
    ) as HarnessSessionReady;

    expect(updated.surfaces['main']!.dataModel['status'], 'ready');
    expect(updated.turns.where((turn) => turn.sender == 'user'), isEmpty);
  });
}
