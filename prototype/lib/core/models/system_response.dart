import 'dart:convert';

/// Observation output returned by a module execution wrapped in `<system_response>` tags.
///
/// Injected back into the model's conversation history during intermediate turns of the
/// autonomous multi-turn execution loop.
/// Conforms to JSON Schema `https://harness.agent/schemas/system-response.schema.json`.
class SystemResponse {
  /// The command that produced this response, matching a [SystemCall.command].
  final String command;

  /// Execution status indicator: strictly `'success'` or `'error'`.
  final String status;

  /// Execution output payload (string, object, or list) returned on success.
  final dynamic data;

  /// Human- and model-readable description of the failure when status is error.
  final String? errorMessage;

  SystemResponse({
    required this.command,
    required this.status,
    this.data,
    this.errorMessage,
  }) {
    if (command.trim().isEmpty) {
      throw ArgumentError('command cannot be empty.');
    }
    if (status != 'success' && status != 'error') {
      throw ArgumentError('status must be "success" or "error", got "$status".');
    }
  }

  /// Convenience getter indicating if execution succeeded without errors.
  bool get isSuccess => status == 'success';

  /// Convenience getter indicating if execution failed.
  bool get isError => status == 'error';

  /// Factory helper for creating a successful [SystemResponse].
  factory SystemResponse.success({
    required String command,
    dynamic data,
  }) {
    return SystemResponse(
      command: command,
      status: 'success',
      data: data,
    );
  }

  /// Factory helper for creating an error [SystemResponse].
  factory SystemResponse.error({
    required String command,
    required String errorMessage,
  }) {
    return SystemResponse(
      command: command,
      status: 'error',
      errorMessage: errorMessage,
    );
  }

  /// Converts the observation into standard `<system_response>` XML markup
  /// for feedback injection into LLM context history.
  String toXmlString() {
    if (isError) {
      final errorPayload = json.encode({
        'error': errorMessage ?? 'Invalid command or malformed JSON',
      });
      return '<system_response command="$command" status="error">\n$errorPayload\n</system_response>';
    }
    final body = data is String ? data : (data != null ? json.encode(data) : '');
    return '<system_response command="$command" status="success">\n$body\n</system_response>';
  }

  /// Serializes the response to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'status': status,
      if (data != null) 'data': data,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  /// Deserializes a system response from a JSON map.
  factory SystemResponse.fromJson(Map<String, dynamic> json) {
    return SystemResponse(
      command: json['command'] as String,
      status: json['status'] as String,
      data: json['data'],
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemResponse &&
          runtimeType == other.runtimeType &&
          command == other.command &&
          status == other.status &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => command.hashCode ^ status.hashCode ^ (errorMessage?.hashCode ?? 0);
}
