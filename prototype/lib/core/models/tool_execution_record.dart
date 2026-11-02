import 'package:equatable/equatable.dart';
import 'system_call.dart';

/// Recorded status and observation payload for an individual system call execution.
///
/// Persisted in [Turn.toolCalls] to provide auditability and inspection of
/// module/skill executions both during real-time running and after turn completion.
class ToolExecutionRecord extends Equatable {
  /// The structured system call dispatched to the engine.
  final SystemCall call;

  /// Current execution status: `'running'`, `'success'`, or `'error'`.
  final String status;

  /// Optional error description when status is error.
  final String? errorMessage;

  /// Optional output data or response observation from execution.
  final dynamic output;

  const ToolExecutionRecord({
    required this.call,
    required this.status,
    this.errorMessage,
    this.output,
  });

  bool get isRunning => status == 'running';
  bool get isSuccess => status == 'success';
  bool get isError => status == 'error';

  ToolExecutionRecord copyWith({
    SystemCall? call,
    String? status,
    String? errorMessage,
    dynamic output,
  }) {
    return ToolExecutionRecord(
      call: call ?? this.call,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      output: output ?? this.output,
    );
  }

  /// Serializes the record to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'call': call.toJson(),
      'status': status,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (output != null) 'output': output,
    };
  }

  /// Deserializes a record from a JSON map.
  factory ToolExecutionRecord.fromJson(Map<String, dynamic> json) {
    return ToolExecutionRecord(
      call: SystemCall.fromJson(Map<String, dynamic>.from(json['call'] as Map)),
      status: json['status'] as String? ?? 'success',
      errorMessage: json['errorMessage'] as String?,
      output: json['output'],
    );
  }

  @override
  List<Object?> get props => [
        call.command,
        call.parameters,
        status,
        errorMessage,
        output,
      ];
}

