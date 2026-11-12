import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

class _RetryingProvider extends ModelProvider {
  @override
  ProviderConfig get config => ProviderConfig(
        id: 'retrying',
        providerType: 'gemini',
        displayName: 'Retrying Mock',
        modelName: 'retrying-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    emitRetry(const ModelRetryEvent(
      phase: ModelRetryPhase.waiting,
      attempt: 1,
      maxAttempts: 10,
      delay: Duration(milliseconds: 100),
      reason: 'HTTP 429',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    emitRetry(const ModelRetryEvent(
      phase: ModelRetryPhase.attempting,
      attempt: 2,
      maxAttempts: 10,
    ));
    return '<system_call>{"command": "send_ui_message", "parameters": {"message": "Recovered"}}</system_call>';
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
  test('shows Retrying while waiting and Thinking when the attempt resumes',
      () async {
    final provider = _RetryingProvider();
    addTearDown(provider.dispose);

    final engine = HarnessEngine(
      router: CommandRouter(),
      contextBuilder: ContextBuilder(),
      modelProvider: provider,
    );
    final bloc = HarnessSessionBloc(engine: engine);
    addTearDown(bloc.close);

    final states = <HarnessSessionState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    bloc.add(const InitializeSessionEvent(sessionId: 'sess_retry_status'));
    await bloc.stream.firstWhere((state) => state is HarnessSessionReady);

    final finished = bloc.stream
        .firstWhere((state) =>
            state is HarnessSessionReady && state.turns.length == 2)
        .timeout(const Duration(seconds: 5));

    bloc.add(const SubmitUserPromptEvent('Retry this'));
    final finalState = await finished;

    final executingStates = states.whereType<HarnessTurnExecuting>().toList();
    expect(
      executingStates.any(
        (state) => state.statusMessage.startsWith('Retrying...'),
      ),
      isTrue,
    );
    expect(
      executingStates.any((state) => state.statusMessage == 'Thinking...'),
      isTrue,
    );
    expect(finalState.turns.last.text, 'Recovered');
  });
}
