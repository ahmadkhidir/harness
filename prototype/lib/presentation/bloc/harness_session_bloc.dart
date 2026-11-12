import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/engine_events.dart';
import '../../core/engine/harness_engine.dart';
import '../../core/models/model_token_limits.dart';
import '../../core/models/scheduled_timer.dart';
import '../../core/models/turn.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/timer_service.dart';
import '../../modules/a2ui/a2ui_action_prompt.dart';
import '../../modules/a2ui/a2ui_surface_store.dart';
import '../../providers/model_provider.dart';
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

  StreamSubscription<EngineProgressEvent>? _engineSubscription;
  StreamSubscription<ModelRetryEvent>? _retrySubscription;

  /// Prompt line waiting to be appended to `context.txt` after dispatch.
  String? _pendingUserContextPrompt;

  /// Session receiving [_pendingUserContextPrompt].
  String? _pendingUserContextSessionId;

  /// Timer whose self-prompt is currently executing.
  ScheduledTimer? _activeTimer;

  /// Live A2UI surfaces for the active session.
  A2UISurfaceStore _surfaceStore = A2UISurfaceStore();

  HarnessSessionBloc({
    required this.engine,
    this.keyStorage,
    this.sessionService,
    this.timerService,
  }) : super(const HarnessSessionInitial()) {
    on<InitializeSessionEvent>(_onInitializeSession);
    on<SwitchSessionEvent>(_onSwitchSession);
    on<SubmitUserPromptEvent>(_onSubmitUserPrompt);
    on<RunScheduledTimerEvent>(_onRunScheduledTimer);
    on<HandleA2UIActionEvent>(_onHandleA2UIAction);
    on<UpdateA2UISurfaceDataEvent>(_onUpdateA2UISurfaceData);
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
    _surfaceStore = _replaySurfaces(existingTurns);
    emit(HarnessSessionReady(
      sessionId: targetId,
      turns: existingTurns,
      surfaces: _surfaceStore.surfaces,
    ));
    await _drainTimers(targetId, emit);
  }

  Future<void> _onSwitchSession(
    SwitchSessionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    await _retrySubscription?.cancel();
    _retrySubscription = null;
    final interruptedTimer = _activeTimer;
    _activeTimer = null;
    if (interruptedTimer != null) {
      await timerService?.markCompleted(interruptedTimer);
    }

    if (sessionService != null) {
      await sessionService!.setActiveSessionId(event.sessionId);
      final turns = await sessionService!.loadTurns(event.sessionId);
      _surfaceStore = _replaySurfaces(turns);
      emit(HarnessSessionReady(
        sessionId: event.sessionId,
        turns: turns,
        surfaces: _surfaceStore.surfaces,
      ));
    } else {
      _surfaceStore = A2UISurfaceStore();
      emit(HarnessSessionReady(
        sessionId: event.sessionId,
        turns: const [],
        surfaces: _surfaceStore.surfaces,
      ));
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
  /// Direct prompts are persisted as visible user turns. A2UI actions and timer
  /// prompts pass `showUserTurn: false`: the prompt reaches the model and
  /// `context.txt`, but no user bubble or `turns.json` entry is created.
  Future<void> _startPrompt(
    String prompt,
    String? explicitApiKey,
    Emitter<HarnessSessionState> emit, {
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
      surfaces: _surfaceStore.surfaces,
      toolIndicators: const [],
      statusMessage: 'Thinking...',
    ));

    final activeProviderId = engine.modelProvider.config.id;
    final effectiveApiKey =
        explicitApiKey ?? await keyStorage?.getApiKey(activeProviderId);

    _pendingUserContextPrompt = prompt;
    _pendingUserContextSessionId = currentSessionId;

    await _engineSubscription?.cancel();
    await _retrySubscription?.cancel();
    _retrySubscription = engine.modelProvider.retryEvents.listen((retry) {
      if (isClosed) return;
      add(SessionEngineProgressReceived(EngineModelRetryStatus(
        waiting: retry.phase == ModelRetryPhase.waiting,
        attempt: retry.attempt,
        maxAttempts: retry.maxAttempts,
        delay: retry.delay,
      )));
    });
    _engineSubscription = engine
        .executeTurn(
          userPrompt: prompt,
          sessionId: currentSessionId,
          apiKey: effectiveApiKey,
          sessionTranscript: transcript,
          surfaceStore: _surfaceStore,
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

  /// Sends an A2UI component action directly to the model.
  ///
  /// The action is not added to the chat stream or `turns.json`. Its structured
  /// prompt is appended to `context.txt` as the current user request. The
  /// surface data model carried by the event is applied first so the model
  /// receives the component's current state.
  Future<void> _onHandleA2UIAction(
    HandleA2UIActionEvent event,
    Emitter<HarnessSessionState> emit,
  ) async {
    final action = event.action.trim();
    if (action.isEmpty) return;

    await _startPrompt(
      buildA2UIActionPrompt(
        surfaceId: event.surfaceId,
        componentId: event.componentId,
        action: action,
        payload: event.dataModel,
      ),
      null,
      emit,
      showUserTurn: false,
    );
  }

  /// Applies a local component value change without starting a model turn.
  ///
  /// Used by stateful inputs while the user is editing, such as typing in a
  /// text field or dragging a slider. The value is written to the live surface
  /// data model so every binding reflects it immediately.
  void _onUpdateA2UISurfaceData(
    UpdateA2UISurfaceDataEvent event,
    Emitter<HarnessSessionState> emit,
  ) {
    _surfaceStore.setDataModelValue(
      event.surfaceId,
      event.path,
      event.value,
    );
    _emitWithSurfaces(emit);
  }

  /// Re-emits the current session state with the latest live surfaces.
  void _emitWithSurfaces(Emitter<HarnessSessionState> emit) {
    final current = state;
    if (current is HarnessTurnExecuting) {
      emit(HarnessTurnExecuting(
        sessionId: current.sessionId ?? 'sess_default',
        turns: current.turns,
        surfaces: _surfaceStore.surfaces,
        toolIndicators: current.toolIndicators,
        statusMessage: current.statusMessage,
      ));
      return;
    }
    emit(HarnessSessionReady(
      sessionId: current.sessionId ?? 'sess_default',
      turns: current.turns,
      surfaces: _surfaceStore.surfaces,
    ));
  }

  /// Rebuilds live A2UI surfaces by replaying persisted A2UI turns.
  A2UISurfaceStore _replaySurfaces(List<Turn> turns) {
    final store = A2UISurfaceStore();
    for (final turn in turns) {
      if (!turn.isA2UI) continue;
      final messages = turn.a2uiPayload?['messages'];
      if (messages is List && messages.isNotEmpty) {
        store.applyMessages(messages);
      }
    }
    return store;
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
        : (isLocal ? localContextWindowTokensFor(config) : 100000);
    final rawBytes = (tokens * 0.4 * 3.5).round();
    final cap = isLocal ? 32000 : 200000;
    return rawBytes.clamp(4000, cap);
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
          surfaces: _surfaceStore.surfaces,
          toolIndicators: currentExecuting.toolIndicators,
          statusMessage: 'Thinking...',
        ));
      }
    } else if (progress is EngineModelRetryStatus) {
      if (state is HarnessTurnExecuting) {
        final currentExecuting = state as HarnessTurnExecuting;
        emit(HarnessTurnExecuting(
          sessionId: currentSessionId,
          turns: currentTurns,
          surfaces: currentExecuting.surfaces,
          toolIndicators: currentExecuting.toolIndicators,
          statusMessage: progress.waiting
              ? 'Retrying... (${progress.attempt}/${progress.maxAttempts})'
              : 'Thinking...',
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
        surfaces: _surfaceStore.surfaces,
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
          surfaces: _surfaceStore.surfaces,
          toolIndicators: updatedIndicators,
          statusMessage: 'Processed ${progress.call.command}',
        ));
      }
    } else if (progress is EngineTurnCompleted) {
      await _retrySubscription?.cancel();
      _retrySubscription = null;
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
        surfaces: _surfaceStore.surfaces,
      ));
      await _drainTimers(currentSessionId, emit);
    } else if (progress is EngineErrorOccurred) {
      await _retrySubscription?.cancel();
      _retrySubscription = null;
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
        surfaces: _surfaceStore.surfaces,
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
    await _retrySubscription?.cancel();
    _retrySubscription = null;
    final cancelledTimer = _activeTimer;
    _activeTimer = null;
    if (cancelledTimer != null) {
      await timerService?.markCompleted(cancelledTimer);
    }
    emit(HarnessSessionReady(
      sessionId: state.sessionId ?? 'sess_default',
      turns: state.turns,
      surfaces: _surfaceStore.surfaces,
    ));
  }

  @override
  Future<void> close() async {
    await _engineSubscription?.cancel();
    await _retrySubscription?.cancel();
    return super.close();
  }
}

