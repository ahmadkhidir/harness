import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/engine_events.dart';
import '../../core/engine/harness_engine.dart';
import '../../core/models/turn.dart';
import 'harness_session_event.dart';
import 'harness_session_state.dart';

/// BLoC coordinating the reactive session lifecycle and multi-turn execution events.
///
/// Implements the presentation state management defined in `docs/Harness/architecture.md`
/// and acceptance criteria for FEAT-001:
/// - Dispatches progressive events to update tool indicators on the screen in real time.
/// - Streams engine states between `HarnessTurnExecuting` and `HarnessSessionReady`.
class HarnessSessionBloc
    extends Bloc<HarnessSessionEvent, HarnessSessionState> {
  final HarnessEngine engine;
  StreamSubscription<EngineProgressEvent>? _engineSubscription;

  HarnessSessionBloc({required this.engine})
      : super(const HarnessSessionInitial()) {
    on<InitializeSessionEvent>(_onInitializeSession);
    on<SubmitUserPromptEvent>(_onSubmitUserPrompt);
    on<SessionEngineProgressReceived>(_onEngineProgressReceived);
    on<CancelActiveTurnEvent>(_onCancelActiveTurn);
  }

  void _onInitializeSession(
    InitializeSessionEvent event,
    Emitter<HarnessSessionState> emit,
  ) {
    final sessionId =
        event.sessionId ?? 'sess_${DateTime.now().millisecondsSinceEpoch}';
    emit(HarnessSessionReady(sessionId: sessionId, turns: const []));
  }

  Future<void> _onSubmitUserPrompt(
    SubmitUserPromptEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    final currentSessionId =
        state.sessionId ?? 'sess_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistically record user prompt turn in the chat history
    final userTurn = Turn(
      id: 'turn_user_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: currentSessionId,
      timestamp: DateTime.now().toUtc(),
      sender: 'user',
      contentType: 'text',
      text: event.prompt,
    );

    final updatedTurns = List<Turn>.from(state.turns)..add(userTurn);

    emit(HarnessTurnExecuting(
      sessionId: currentSessionId,
      turns: updatedTurns,
      toolIndicators: const [],
      statusMessage: 'Thinking...',
    ));

    await _engineSubscription?.cancel();
    _engineSubscription = engine
        .executeTurn(
          userPrompt: event.prompt,
          sessionId: currentSessionId,
          apiKey: event.apiKey,
        )
        .listen(
          (progressEvent) => add(SessionEngineProgressReceived(progressEvent)),
          onError: (error) => add(
            SessionEngineProgressReceived(
              EngineErrorOccurred('Unexpected stream error: $error'),
            ),
          ),
        );
  }

  void _onEngineProgressReceived(
    SessionEngineProgressReceived event,
    Emitter<HarnessSessionState> emit,
  ) {
    final progress = event.progressEvent;
    final currentSessionId = state.sessionId ?? 'sess_default';
    final currentTurns = state.turns;

    if (progress is EngineModelGenerating) {
      if (state is HarnessTurnExecuting) {
        final currentExecuting = state as HarnessTurnExecuting;
        emit(HarnessTurnExecuting(
          sessionId: currentSessionId,
          turns: currentTurns,
          toolIndicators: currentExecuting.toolIndicators,
          statusMessage: 'Thinking...',
        ));
      }
    } else if (progress is EngineSystemCallStarted) {
      final currentIndicators = state is HarnessTurnExecuting
          ? List<ToolExecutionIndicator>.from(
              (state as HarnessTurnExecuting).toolIndicators,
            )
          : <ToolExecutionIndicator>[];

      currentIndicators.add(ToolExecutionIndicator(
        call: progress.call,
        status: 'running',
      ));

      emit(HarnessTurnExecuting(
        sessionId: currentSessionId,
        turns: currentTurns,
        toolIndicators: currentIndicators,
        statusMessage: 'Executing ${progress.call.command}...',
      ));
    } else if (progress is EngineSystemCallFinished) {
      if (state is HarnessTurnExecuting) {
        final currentExecuting = state as HarnessTurnExecuting;
        final updatedIndicators = currentExecuting.toolIndicators.map((ind) {
          if (ind.call.command == progress.call.command && ind.isRunning) {
            return ind.copyWith(
              status: progress.response.isSuccess ? 'success' : 'error',
              errorMessage: progress.response.errorMessage,
            );
          }
          return ind;
        }).toList();

        emit(HarnessTurnExecuting(
          sessionId: currentSessionId,
          turns: currentTurns,
          toolIndicators: updatedIndicators,
          statusMessage: 'Processed ${progress.call.command}',
        ));
      }
    } else if (progress is EngineTurnCompleted) {
      final updatedTurns = List<Turn>.from(currentTurns)..add(progress.turn);
      emit(HarnessSessionReady(
        sessionId: currentSessionId,
        turns: updatedTurns,
      ));
    } else if (progress is EngineErrorOccurred) {
      emit(HarnessSessionError(
        sessionId: currentSessionId,
        turns: currentTurns,
        errorMessage: progress.message,
      ));
    }
  }

  Future<void> _onCancelActiveTurn(
    CancelActiveTurnEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    emit(HarnessSessionReady(
      sessionId: state.sessionId ?? 'sess_default',
      turns: state.turns,
    ));
  }

  @override
  Future<void> close() async {
    await _engineSubscription?.cancel();
    return super.close();
  }
}

