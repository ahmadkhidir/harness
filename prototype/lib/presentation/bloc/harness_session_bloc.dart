import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/engine_events.dart';
import '../../core/engine/harness_engine.dart';
import '../../core/models/system_response.dart';
import '../../core/models/turn.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../data/services/session_service.dart';
import '../../modules/platform_actions/a2ui_event_router.dart';
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

  /// Routes A2UI button taps to native platform actions or new user turns.
  final A2UIEventRouter a2uiEventRouter;

  StreamSubscription<EngineProgressEvent>? _engineSubscription;

  HarnessSessionBloc({
    required this.engine,
    this.keyStorage,
    this.sessionService,
    A2UIEventRouter? a2uiEventRouter,
  })  : a2uiEventRouter = a2uiEventRouter ?? const A2UIEventRouter(),
        super(const HarnessSessionInitial()) {
    on<InitializeSessionEvent>(_onInitializeSession);
    on<SwitchSessionEvent>(_onSwitchSession);
    on<SubmitUserPromptEvent>(_onSubmitUserPrompt);
    on<HandleA2UIActionEvent>(_onHandleA2UIAction);
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
    await _startPrompt(event.prompt, event.apiKey, emit);
  }

  /// Starts an engine turn for [prompt].
  ///
  /// Direct prompts are persisted as visible user turns. A2UI selections pass
  /// an [actionLabel] so the transcript shows a compact action receipt while
  /// [prompt] (the structured payload) reaches the model and `context.txt`.
  Future<void> _startPrompt(
    String prompt,
    String? explicitApiKey,
    Emitter<HarnessSessionState> emit, {
    String? actionLabel,
  }) async {
    final currentSessionId =
        state.sessionId ?? 'sess_${DateTime.now().millisecondsSinceEpoch}';

    final priorTurns = List<Turn>.from(state.turns);
    List<Turn> updatedTurns;

    if (actionLabel != null) {
      final actionTurn = Turn(
        id: 'turn_action_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: currentSessionId,
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'action',
        text: actionLabel,
      );

      if (sessionService != null) {
        await sessionService!.appendActionTurn(
          currentSessionId,
          actionTurn,
          prompt,
        );
      }

      updatedTurns = List<Turn>.from(priorTurns)..add(actionTurn);
    } else {
      // Optimistically record user prompt turn in the chat history.
      final userTurn = Turn(
        id: 'turn_user_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: currentSessionId,
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'text',
        text: prompt,
      );

      // Dual-write visible user prompts to disk.
      if (sessionService != null) {
        await sessionService!.appendTurn(currentSessionId, userTurn);
      }

      updatedTurns = List<Turn>.from(priorTurns)..add(userTurn);
    }

    emit(HarnessTurnExecuting(
      sessionId: currentSessionId,
      turns: updatedTurns,
      toolIndicators: const [],
      statusMessage: 'Thinking...',
    ));

    final activeProviderId = engine.modelProvider.config.id;
    final effectiveApiKey =
        explicitApiKey ?? await keyStorage?.getApiKey(activeProviderId);

    await _engineSubscription?.cancel();
    _engineSubscription = engine
        .executeTurn(
          userPrompt: prompt,
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

  /// Routes an A2UI component tap according to FEAT-007.
  ///
  /// Platform-prefixed actions execute immediately and never enter the model
  /// loop. Conversational actions are converted into a structured user prompt
  /// and submitted as a fresh engine turn.
  Future<void> _onHandleA2UIAction(
    HandleA2UIActionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    final route = a2uiEventRouter.resolve(event.action, event.dataModel);

    switch (route.kind) {
      case A2UIEventKind.conversationTurn:
        await _startPrompt(
          route.prompt!,
          null,
          emit,
          actionLabel: _actionLabel(route.action),
        );
        return;
      case A2UIEventKind.platformAction:
        final response = await a2uiEventRouter.executePlatform(route);
        _emitActionNotice(
          emit,
          message: _describePlatformResponse(route.command, response),
          isError: response.isError,
        );
        return;
      case A2UIEventKind.invalid:
        _emitActionNotice(
          emit,
          message: route.errorMessage ?? 'Unable to handle this UI action.',
          isError: true,
        );
        return;
    }
  }

  /// Surfaces a transient platform-action result as [HarnessA2UIActionResolved].
  ///
  /// The chat screen listens for this state to show a snackbar. When a turn is
  /// already executing, the previous state is re-emitted immediately afterwards
  /// so in-flight progress handling keeps its tool indicators and the composer
  /// keeps offering the stop control.
  void _emitActionNotice(
    Emitter<HarnessSessionState> emit, {
    required String message,
    required bool isError,
  }) {
    final previous = state;
    emit(HarnessA2UIActionResolved(
      sessionId: previous.sessionId ?? 'sess_default',
      turns: previous.turns,
      message: message,
      isError: isError,
    ));
    if (previous is HarnessTurnExecuting) {
      emit(previous);
    }
  }

  /// Converts an A2UI action identifier into a human-readable receipt label.
  String _actionLabel(String action) {
    final cleaned = action.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Interface action';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  /// Produces a concise user-facing description of a platform action result.
  String _describePlatformResponse(String? command, SystemResponse response) {
    if (response.isError) {
      return response.errorMessage ?? 'Platform action failed.';
    }
    switch (command) {
      case 'set_alarm':
        return 'Alarm scheduled.';
      case 'schedule_notification':
        return 'Notification scheduled.';
      case 'open_url':
        return 'Link opened.';
      case 'copy_to_clipboard':
        return 'Copied to clipboard.';
      default:
        return 'Action completed.';
    }
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

