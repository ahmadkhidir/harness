/// Specification of a callable command exposed dynamically by an on-device or external module.
///
/// Modules publish their [CommandDefinition] entries to the [CommandRouter], which maintains
/// an internal O(1) command lookup registry and injects the tool catalog into the system prompt.
/// Conforms to JSON Schema `https://harness.agent/schemas/command-definition.schema.json`.
class CommandDefinition {
  /// Exact command name emitted in `<system_call>`, e.g. `load_skill`, `grep`, `send_ui_message`.
  final String command;

  /// Natural language summary of the command explaining when and how the agent should invoke it.
  final String description;

  /// JSON Schema describing the required and optional parameters expected by the command.
  final Map<String, dynamic> parametersSchema;

  CommandDefinition({
    required this.command,
    required this.description,
    required this.parametersSchema,
  }) {
    if (command.trim().isEmpty) {
      throw ArgumentError('command cannot be empty.');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('description cannot be empty.');
    }
  }

  /// Serializes the command definition to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'description': description,
      'parametersSchema': parametersSchema,
    };
  }

  /// Deserializes a command definition from a JSON map.
  factory CommandDefinition.fromJson(Map<String, dynamic> json) {
    return CommandDefinition(
      command: json['command'] as String,
      description: json['description'] as String,
      parametersSchema: json['parametersSchema'] != null
          ? Map<String, dynamic>.from(json['parametersSchema'] as Map)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandDefinition &&
          runtimeType == other.runtimeType &&
          command == other.command &&
          description == other.description;

  @override
  int get hashCode => command.hashCode ^ description.hashCode;
}
