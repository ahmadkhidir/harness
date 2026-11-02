import 'package:equatable/equatable.dart';
import '../../core/models/tool_execution_record.dart';
import '../../core/models/turn.dart';

export '../../core/models/tool_execution_record.dart';

/// Type alias maintaining full backward compatibility with previous ToolExecutionIndicator usages.
typedef ToolExecutionIndicator = ToolExecutionRecord;

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

