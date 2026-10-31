import 'package:equatable/equatable.dart';
import '../../core/models/system_call.dart';
import '../../core/models/turn.dart';

/// Real-time status indicator model for an individual tool system call.
class ToolExecutionIndicator extends Equatable {
  /// The system call being executed.
  final SystemCall call;

  /// Current execution status: `'running'`, `'success'`, or `'error'`.
  final String status;

  /// Optional error description when status is error.
  final String? errorMessage;

  const ToolExecutionIndicator({
    required this.call,
    required this.status,
    this.errorMessage,
  });

  bool get isRunning => status == 'running';
  bool get isSuccess => status == 'success';
  bool get isError => status == 'error';

  ToolExecutionIndicator copyWith({
    String? status,
    String? errorMessage,
  }) {
    return ToolExecutionIndicator(
      call: call,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [call.command, call.parameters, status, errorMessage];
}

/// Base state class for [HarnessSessionBloc].
abstract class HarnessSessionState extends Equatable {
  final String? sessionId;
  final List<Turn> turns;

  const HarnessSessionState({
    this.sessionId,
    this.turns = const [],
  });

  @override
  List<Object?> get props => [sessionId, turns];
}

/// Initial uninitialized session state.
class HarnessSessionInitial extends HarnessSessionState {
  const HarnessSessionInitial();
}

/// Active session ready to receive user prompts.
class HarnessSessionReady extends HarnessSessionState {
  const HarnessSessionReady({
    required super.sessionId,
    super.turns = const [],
  });
}

/// Active turn is currently executing multi-turn tool loops.
class HarnessTurnExecuting extends HarnessSessionState {
  /// Real-time tool indicators showing pending, running, and finished parallel calls.
  final List<ToolExecutionIndicator> toolIndicators;

  /// Human-readable execution phase (e.g. "Thinking...", "Executing 2 tools in parallel...").
  final String statusMessage;

  const HarnessTurnExecuting({
    required super.sessionId,
    required super.turns,
    required this.toolIndicators,
    this.statusMessage = 'Thinking...',
  });

  @override
  List<Object?> get props => [sessionId, turns, toolIndicators, statusMessage];
}

/// An unrecoverable failure occurred during turn execution.
class HarnessSessionError extends HarnessSessionState {
  final String errorMessage;
  final bool isAuthError;
  final bool isMemoryError;

  const HarnessSessionError({
    super.sessionId,
    super.turns = const [],
    required this.errorMessage,
    this.isAuthError = false,
    this.isMemoryError = false,
  });

  @override
  List<Object?> get props => [sessionId, turns, errorMessage, isAuthError, isMemoryError];
}

