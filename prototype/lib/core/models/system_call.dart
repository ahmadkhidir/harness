/// Structured tool call emitted by an LLM within `<system_call>` tags.
///
/// Example raw output:
/// ```xml
/// <system_call>
/// {"command": "grep", "parameters": {"pattern": "TODO", "path": "workspace/"}}
/// </system_call>
/// ```
/// Conforms to JSON Schema `https://harness.agent/schemas/system-call.schema.json`.
class SystemCall {
  /// Target command name resolving to a registered [CommandDefinition].
  final String command;

  /// Arguments dictionary matching the command's parameter schema.
  final Map<String, dynamic> parameters;

  SystemCall({
    required this.command,
    required this.parameters,
  }) {
    if (command.trim().isEmpty) {
      throw ArgumentError('command cannot be empty.');
    }
  }

  /// Serializes the system call to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'parameters': parameters,
    };
  }

  /// Deserializes a system call from a JSON map.
  factory SystemCall.fromJson(Map<String, dynamic> json) {
    return SystemCall(
      command: json['command'] as String,
      parameters: json['parameters'] != null
          ? Map<String, dynamic>.from(json['parameters'] as Map)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemCall &&
          runtimeType == other.runtimeType &&
          command == other.command;

  @override
  int get hashCode => command.hashCode ^ parameters.hashCode;
}
