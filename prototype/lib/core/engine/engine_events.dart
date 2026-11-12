import '../models/system_call.dart';
import '../models/system_response.dart';
import '../models/turn.dart';

/// Base class for all progressive turn execution events emitted by [HarnessEngine].
abstract class EngineProgressEvent {}

/// Emitted when a new turn execution cycle begins with a user prompt.
class EngineTurnStarted extends EngineProgressEvent {
  final String userPrompt;
  EngineTurnStarted(this.userPrompt);
}

/// Emitted while waiting for the LLM to complete generation.
class EngineModelGenerating extends EngineProgressEvent {}

/// Emitted when a transient model request is waiting to retry or resuming.
class EngineModelRetryStatus extends EngineProgressEvent {
  /// True while waiting for the backoff delay; false when the next attempt starts.
  final bool waiting;

  /// Failed attempt number.
  final int attempt;

  /// Maximum number of attempts.
  final int maxAttempts;

  /// Backoff delay for a waiting event.
  final Duration delay;

  EngineModelRetryStatus({
    required this.waiting,
    required this.attempt,
    required this.maxAttempts,
    this.delay = Duration.zero,
  });
}

/// Emitted when a tool system call begins execution.
class EngineSystemCallStarted extends EngineProgressEvent {
  final SystemCall call;
  EngineSystemCallStarted(this.call);
}

/// Emitted when an individual tool system call completes with its observation.
class EngineSystemCallFinished extends EngineProgressEvent {
  final SystemCall call;
  final SystemResponse response;
  EngineSystemCallFinished(this.call, this.response);
}

/// Emitted when the entire turn lifecycle concludes with a finalized [Turn] record.
class EngineTurnCompleted extends EngineProgressEvent {
  final Turn turn;
  EngineTurnCompleted(this.turn);
}

/// Emitted when an unrecoverable failure or turn limit occurs.
class EngineErrorOccurred extends EngineProgressEvent {
  final String message;
  EngineErrorOccurred(this.message);
}
