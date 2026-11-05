import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/engine_events.dart';
import '../../core/engine/harness_engine.dart';
import '../../core/models/scheduled_timer.dart';
import '../../core/models/system_response.dart';
import '../../core/models/turn.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/timer_service.dart';
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

  /// Scheduled self-prompt timers (FEAT-010).
  final TimerService? timerService;

  /// Routes A2UI button taps to native platform actions or new user turns.
  final A2UIEventRouter a2uiEventRouter;

  StreamSubscription<EngineProgressEvent>? _engineSubscription;

  /// Prompt line waiting to be appended to `context.txt` after dispatch.
  String? _pendingUserContextPrompt;

  /// Session receiving [_pendingUserContextPrompt].
  String? _pendingUserContextSessionId;

  /// Timer whose self-prompt is currently executing.
  ScheduledTimer? _activeTimer;

  HarnessSessionBloc({
    required this.engine,
    this.keyStorage,
    this.sessionService,
    this.timerService,
    A2UIEventRouter? a2uiEventRouter,
  })  : a2uiEventRouter = a2uiEventRouter ?? const A2UIEventRouter(),
        super(const HarnessSessionInitial()) {
    on<InitializeSessionEvent>(_onInitializeSession);
    on<SwitchSessionEvent>(_onSwitchSession);
    on<SubmitUserPromptEvent>(_onSubmitUserPrompt);
    on<RunScheduledTimerEvent>(_onRunScheduledTimer);
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
    await _drainTimers(targetId, emit);
  }

  Future<void> _onSwitchSession(
    SwitchSessionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    final interruptedTimer = _activeTimer;
    _activeTimer = null;
    if (interruptedTimer != null) {
      await timerService?.markCompleted(interruptedTimer);
    }

    if (sessionService != null) {
      await sessionService!.setActiveSessionId(event.sessionId);
      final turns = await sessionService!.loadTurns(event.sessionId);
      emit(HarnessSessionReady(sessionId: event.sessionId, turns: turns));
    } else {
      emit(HarnessSessionReady(sessionId: event.sessionId, turns: const []));
    }
    await _drainTimers(event.sessionId, emit);
  }

  Future<void> _onSubmitUserPrompt(
    SubmitUserPromptEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    await _startPrompt(event.prompt, event.apiKey, emit);
  }

  Future<void> _onRunScheduledTimer(
    RunScheduledTimerEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    if (state.sessionId != event.timer.sessionId) return;
    if (state is HarnessTurnExecuting) return;
    await _startPrompt(
      event.timer.prompt,
      null,
      emit,
      showUserTurn: false,
      timer: event.timer,
    );
  }

  /// Starts the next queued timer for [sessionId] when the session is idle.
  Future<void> _drainTimers(
    String sessionId,
    Emitter<HarnessSessionState> emit,
  ) async {
    final service = timerService;
    if (service == null || state is HarnessTurnExecuting) return;

    final queued = await service.queued(sessionId);
    if (queued.isEmpty) return;

    await _startPrompt(
      queued.first.prompt,
      null,
      emit,
      showUserTurn: false,
      timer: queued.first,
    );
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
    bool showUserTurn = true,
    ScheduledTimer? timer,
  }) async {
    final currentSessionId =
        state.sessionId ?? 'sess_${DateTime.now().millisecondsSinceEpoch}';

    final priorTurns = List<Turn>.from(state.turns);

    // Read conversation memory before the current prompt is appended. The
    // context file is the only model-facing history; turns.json is UI-only.
    final transcript = sessionService != null
        ? await sessionService!.readContextTranscript(
            currentSessionId,
            excludePrompt: prompt,
          )
        : '';

    final userTurn = !showUserTurn
        ? null
        : actionLabel != null
            ? Turn(
                id: 'turn_action_${DateTime.now().millisecondsSinceEpoch}',
                sessionId: currentSessionId,
                timestamp: DateTime.now().toUtc(),
                sender: 'user',
                contentType: 'action',
                text: actionLabel,
              )
            : Turn(
                id: 'turn_user_${DateTime.now().millisecondsSinceEpoch}',
                sessionId: currentSessionId,
                timestamp: DateTime.now().toUtc(),
                sender: 'user',
                contentType: 'text',
                text: prompt,
              );

    // UI log only. The matching USER line is appended after dispatch.
    if (userTurn != null && sessionService != null) {
      await sessionService!.appendUiTurn(currentSessionId, userTurn);
    }

    final updatedTurns = userTurn == null
        ? priorTurns
        : (List<Turn>.from(priorTurns)..add(userTurn));

    if (timer != null) {
      _activeTimer = timer;
      await timerService?.markRunning(timer);
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

    _pendingUserContextPrompt = prompt;
    _pendingUserContextSessionId = currentSessionId;

    await _engineSubscription?.cancel();
    _engineSubscription = engine
        .executeTurn(
          userPrompt: prompt,
          sessionId: currentSessionId,
          apiKey: effectiveApiKey,
          sessionTranscript: transcript,
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

  /// Computes the transcript budget used for compaction.
  ///
  /// Remote providers are assumed to have a 100k-token window; local models use
  /// their configured window or 8k. The transcript targets 40% of the window
  /// (about 3.5 chars per token), with caps that keep prompts sane.
  int _contextBudgetBytes() {
    final config = engine.modelProvider.config;
    final isLocal = config.providerType == 'local_device';
    final configuredWindow = config.extraConfig['contextWindowTokens'];
    final tokens = configuredWindow is int && configuredWindow > 0
        ? configuredWindow
        : (isLocal ? 8192 : 100000);
    final rawBytes = (tokens * 0.4 * 3.5).round();
    final cap = isLocal ? 32000 : 200000;
    return rawBytes.clamp(4000, cap);
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

    if (progress is EngineTurnStarted) {
      final pendingPrompt = _pendingUserContextPrompt;
      final pendingSession = _pendingUserContextSessionId;
      if (pendingPrompt != null &&
          pendingSession != null &&
          sessionService != null) {
        await sessionService!.appendUserContextLine(
          pendingSession,
          pendingPrompt,
        );
      }
      _pendingUserContextPrompt = null;
      _pendingUserContextSessionId = null;
    } else if (progress is EngineModelGenerating) {
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
      if (sessionService != null) {
        await sessionService!.appendToolObservation(
          currentSessionId,
          command: progress.call.command,
          parameters: progress.call.parameters,
          success: progress.response.isSuccess,
          error: progress.response.errorMessage,
          output: progress.response.data,
        );
      }

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

      final completedTimer = _activeTimer;
      _activeTimer = null;
      if (completedTimer != null) {
        await timerService?.markCompleted(completedTimer);
      }

      if (sessionService != null) {
        await sessionService!.appendTurn(currentSessionId, turnWithTools);
        await sessionService!.checkAndCompact(
          currentSessionId,
          thresholdBytes: _contextBudgetBytes(),
        );
      }

      final updatedTurns = List<Turn>.from(currentTurns)..add(turnWithTools);
      emit(HarnessSessionReady(
        sessionId: currentSessionId,
        turns: updatedTurns,
      ));
      await _drainTimers(currentSessionId, emit);
    } else if (progress is EngineErrorOccurred) {
      final failedTimer = _activeTimer;
      _activeTimer = null;
      if (failedTimer != null) {
        await timerService?.markCompleted(failedTimer);
      }
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
    final cancelledTimer = _activeTimer;
    _activeTimer = null;
    if (cancelledTimer != null) {
      await timerService?.markCompleted(cancelledTimer);
    }
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

