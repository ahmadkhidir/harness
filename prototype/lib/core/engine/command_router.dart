import '../models/command_definition.dart';
import '../models/system_call.dart';
import '../models/system_response.dart';
import '../../modules/base/harness_module.dart';

/// Progress callback invoked whenever an individual system call completes during a turn.
typedef CommandProgressCallback = void Function(
  SystemCall call,
  SystemResponse response,
);

/// Central command routing registry and execution coordinator.
///
/// Implements the parallel command dispatcher specified in `docs/Harness/architecture.md`:
/// - Maps command names to their source modules in an internal $O(1)$ lookup table.
/// - Coordinates parallel execution of multiple independent `<system_call>` blocks via `Future.wait`.
/// - Isolates unhandled exceptions so one failed command does not crash sibling tasks.
class CommandRouter {
  final Map<String, HarnessModule> _registry = {};
  final Map<String, CommandDefinition> _commandDefinitions = {};

  /// Registers a module and all of its callable commands into the routing table.
  ///
  /// Throws [StateError] if a command name collision occurs across modules.
  void registerModule(HarnessModule module) {
    for (final cmd in module.commands) {
      if (_registry.containsKey(cmd.command)) {
        throw StateError(
          'Command collision: "${cmd.command}" is already registered by "${_registry[cmd.command]!.moduleName}".',
        );
      }
      _registry[cmd.command] = module;
      _commandDefinitions[cmd.command] = cmd;
    }
  }

  /// Returns an immutable list of all registered command specifications for prompt injection.
  List<CommandDefinition> get allCommandDefinitions =>
      List.unmodifiable(_commandDefinitions.values);

  /// Checks whether a command name is registered in the routing table.
  bool hasCommand(String command) => _registry.containsKey(command);

  /// Dispatches a single system call to its owning module.
  ///
  /// Catches any unhandled module exceptions and wraps them in a structured error [SystemResponse].
  Future<SystemResponse> executeCall(SystemCall call) async {
    if (call.command == 'malformed_json_error') {
      return SystemResponse.error(
        command: call.command,
        errorMessage: 'Invalid command or malformed JSON: ${call.parameters['error'] ?? 'Malformed JSON'}',
      );
    }

    final module = _registry[call.command];
    if (module == null) {
      return SystemResponse.error(
        command: call.command,
        errorMessage: 'Unknown command or invalid JSON: "${call.command}" is not registered in Harness.',
      );
    }

    try {
      return await module.executeCommand(call.command, call.parameters);
    } catch (e, stack) {
      // Catch unhandled module exceptions so an individual tool failure returns
      // an error observation without crashing the engine or cancelling sibling tasks.
      return SystemResponse.error(
        command: call.command,
        errorMessage: 'Unhandled exception executing "${call.command}": $e\n$stack',
      );
    }
  }

  /// Executes multiple system calls concurrently in parallel using `Future.wait`.
  ///
  /// Invokes [onProgress] as each call completes so the UI can update progress indicators.
  Future<List<SystemResponse>> executeCallsParallel(
    List<SystemCall> calls, {
    CommandProgressCallback? onProgress,
  }) async {
    if (calls.isEmpty) return [];

    final futures = calls.map((call) async {
      final response = await executeCall(call);
      onProgress?.call(call, response);
      return response;
    });

    return await Future.wait(futures);
  }
}
