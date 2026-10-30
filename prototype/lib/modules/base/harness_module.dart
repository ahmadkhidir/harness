import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';

/// Base contract for all on-device and external bridge modules in Harness.
///
/// Modules expose one or more [CommandDefinition] entries that are registered in the
/// [CommandRouter]. When an LLM outputs a matching `<system_call>`, the router dispatches
/// execution to the module's [executeCommand] method.
abstract class HarnessModule {
  /// Unique identifier of the module (e.g. `'skills'`, `'storage'`, `'session'`).
  String get moduleName;

  /// The list of callable commands registered and exposed by this module.
  List<CommandDefinition> get commands;

  /// Executes an authorized command with the given argument parameters.
  ///
  /// Returns a [SystemResponse] containing the status (`'success'` or `'error'`)
  /// and the data payload or error message.
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  );
}
