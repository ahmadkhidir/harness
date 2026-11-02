import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/engine_events.dart';
import '../../core/engine/harness_engine.dart';
import '../../core/models/turn.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../data/services/session_service.dart';
import 'harness_session_event.dart';
import 'harness_session_state.dart';

/// BLoC coordinating the reactive session lifecycle and multi-turn execution events.
///
/// Implements the presentation state management defined in `docs/Harness/architecture.md`
/// and acceptance criteria for FEAT-001, FEAT-002, and FEAT-005:
/// - Dispatches progressive events to update tool indicators on the screen in real time.
/// - Resolves API keys from [KeyStorageService] when not passed directly in the event.
/// - Flags authentication errors for direct user navigation to Settings.
/// - Coordinates dual-file session persistence and context compaction with [SessionService].
class HarnessSessionBloc
    extends Bloc<HarnessSessionEvent, HarnessSessionState> {
  final HarnessEngine engine;
  final KeyStorageService? keyStorage;
  final SessionService? sessionService;
  StreamSubscription<EngineProgressEvent>? _engineSubscription;

  HarnessSessionBloc({
    required this.engine,
    this.keyStorage,
    this.sessionService,
  }) : super(const HarnessSessionInitial()) {
    on<InitializeSessionEvent>(_onInitializeSession);
    on<SwitchSessionEvent>(_onSwitchSession);
    on<SubmitUserPromptEvent>(_onSubmitUserPrompt);
    on<SessionEngineProgressReceived>(_onEngineProgressReceived);
    on<CancelActiveTurnEvent>(_onCancelActiveTurn);
  }

  Future<void> _onInitializeSession(
    InitializeSessionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    String? targetId = event.sessionId;
    if (targetId == null && sessionService != null) {
      targetId = await sessionService!.getActiveSessionId();
      if (targetId == null) {
        final session = await sessionService!.createSession(title: 'New Session');
        targetId = session.id;
      }
    }
    targetId ??= 'sess_${DateTime.now().millisecondsSinceEpoch}';

    List<Turn> existingTurns = [];
    if (sessionService != null) {
      existingTurns = await sessionService!.loadTurns(targetId);
    }
    emit(HarnessSessionReady(sessionId: targetId, turns: existingTurns));
  }

  Future<void> _onSwitchSession(
    SwitchSessionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;

    if (sessionService != null) {
      await sessionService!.setActiveSessionId(event.sessionId);
      final turns = await sessionService!.loadTurns(event.sessionId);
      emit(HarnessSessionReady(sessionId: event.sessionId, turns: turns));
    } else {
      emit(HarnessSessionReady(sessionId: event.sessionId, turns: const []));
    }
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

    // Dual-write user prompt to disk
    if (sessionService != null) {
      await sessionService!.appendTurn(currentSessionId, userTurn);
    }

    final priorTurns = List<Turn>.from(state.turns);
    final updatedTurns = List<Turn>.from(priorTurns)..add(userTurn);

    emit(HarnessTurnExecuting(
      sessionId: currentSessionId,
      turns: updatedTurns,
      toolIndicators: const [],
      statusMessage: 'Thinking...',
    ));

    final activeProviderId = engine.modelProvider.config.id;
    final effectiveApiKey = event.apiKey ?? await keyStorage?.getApiKey(activeProviderId);

    await _engineSubscription?.cancel();
    _engineSubscription = engine
        .executeTurn(
          userPrompt: event.prompt,
          sessionId: currentSessionId,
          apiKey: effectiveApiKey,
          recentHistory: priorTurns,
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

  Future<void> _onEngineProgressReceived(
    SessionEngineProgressReceived event,
    Emitter<HarnessSessionState> emit,
  ) async {
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
              output: progress.response.data,
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
      final turnWithTools = progress.turn.toolCalls.isNotEmpty
          ? progress.turn
          : (state is HarnessTurnExecuting &&
                  (state as HarnessTurnExecuting).toolIndicators.isNotEmpty
              ? progress.turn.copyWith(
                  toolCalls: (state as HarnessTurnExecuting).toolIndicators,
                )
              : progress.turn);

      if (sessionService != null) {
        await sessionService!.appendTurn(currentSessionId, turnWithTools);
        await sessionService!.checkAndCompact(currentSessionId);
      }

      final updatedTurns = List<Turn>.from(currentTurns)..add(turnWithTools);
      emit(HarnessSessionReady(
        sessionId: currentSessionId,
        turns: updatedTurns,
      ));
    } else if (progress is EngineErrorOccurred) {
      final msg = progress.message;
      final isAuth = msg.toLowerCase().contains('api key') ||
          msg.toLowerCase().contains('authentication') ||
          msg.toLowerCase().contains('unauthorized') ||
          msg.toLowerCase().contains('authorization');
      final isMem = msg.toLowerCase().contains('memory limit') ||
          msg.toLowerCase().contains('memory bounds') ||
          msg.toLowerCase().contains('exceeded mobile memory');

      emit(HarnessSessionError(
        sessionId: currentSessionId,
        turns: currentTurns,
        errorMessage: progress.message,
        isAuthError: isAuth,
        isMemoryError: isMem,
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

