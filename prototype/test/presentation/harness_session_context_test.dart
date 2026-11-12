import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/base/harness_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

class _NoopModule extends HarnessModule {
  @override
  String get moduleName => 'noop';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'noop',
          description: 'Test tool',
          parametersSchema: const {'type': 'object'},
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    return SystemResponse.success(command: command, data: 'ok');
  }
}

class _ScriptedProvider extends ModelProvider {
  final List<String> script;
  int _index = 0;

  _ScriptedProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted_context',
        providerType: 'gemini',
        displayName: 'Scripted Context Model',
        modelName: 'scripted-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    return _index < script.length ? script[_index++] : script.last;
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
  test('a turn writes USER, TOOL, and AGENT lines to context.txt in order',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('harness_bloc_ctx_');
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

    final engine = HarnessEngine(
      router: CommandRouter()..registerModule(_NoopModule()),
      contextBuilder: ContextBuilder(),
      modelProvider: _ScriptedProvider([
        '<system_call>{"command": "noop", "parameters": {"x": 1}}</system_call>',
        '<system_call>{"command": "send_ui_message", "parameters": {"message": "Done."}}</system_call>',
      ]),
    );

    final bloc = HarnessSessionBloc(
      engine: engine,
      sessionService: sessionService,
    );
    addTearDown(bloc.close);

    final readyFuture = bloc.stream.firstWhere(
      (state) => state is HarnessSessionReady && state.turns.length >= 2,
    );

    bloc.add(const SubmitUserPromptEvent('run the noop tool'));
    final ready = await readyFuture as HarnessSessionReady;

    final context = fileSystem
        .sessionContextFile(ready.sessionId!)
        .readAsStringSync();

    final userIndex = context.indexOf('USER: run the noop tool');
    final toolIndex = context.indexOf(
      'TOOL: {"command":"noop","parameters":{"x":1},"status":"success","output":"ok","truncated":false}',
    );
    final agentIndex = context.indexOf('AGENT: Done.');

    expect(userIndex, greaterThanOrEqualTo(0));
    expect(toolIndex, greaterThan(userIndex));
    expect(agentIndex, greaterThan(toolIndex));

    // turns.json remains UI-only: no tool turn is recorded there.
    final turns = await sessionService.loadTurns(ready.sessionId!);
    expect(turns.map((turn) => turn.sender), ['user', 'agent']);
  });
}
