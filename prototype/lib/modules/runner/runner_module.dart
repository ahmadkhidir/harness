import 'dart:async';

import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../base/harness_module.dart';
import 'runner_provider.dart';

/// Exposes external script execution as the `execute_script` command.
///
/// Implements FEAT-008. Scripts never run inside the mobile process: every call
/// is delegated to a [RunnerProvider] resolved at execution time, so changing
/// the configured endpoint on the settings screen takes effect immediately.
class RunnerModule extends HarnessModule {
  /// Resolves the active runner, or null when no endpoint is configured.
  ///
  /// Implementations may throw [RunnerException] to explain configuration
  /// problems.
  final Future<RunnerProvider?> Function() runnerProviderFactory;

  /// Creates a module with the supplied runner factory.
  RunnerModule({required this.runnerProviderFactory});

  /// Languages supported by the external runner.
  static const Set<String> supportedLanguages = {'python', 'node', 'bash'};

  @override
  String get moduleName => 'runner';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'execute_script',
          description:
              'Executes Python, Node.js, or Bash code in an external sandbox and returns stdout, stderr, and the exit code.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'language': {
                'type': 'string',
                'enum': ['python', 'node', 'bash'],
                'description': 'Script language.',
              },
              'code': {
                'type': 'string',
                'minLength': 1,
                'description': 'Source code to execute.',
              },
              'env': {
                'type': 'object',
                'additionalProperties': {'type': 'string'},
                'description': 'Optional environment variables.',
              },
              'timeoutSeconds': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 120,
                'description': 'Execution timeout in seconds. Defaults to 30.',
              },
            },
            'required': ['language', 'code'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    if (command != 'execute_script') {
      return SystemResponse.error(
        command: command,
        errorMessage: 'Unrecognized runner command: "$command".',
      );
    }

    final rawLanguage = parameters['language'];
    final language = rawLanguage is String ? rawLanguage.trim().toLowerCase() : '';
    if (!supportedLanguages.contains(language)) {
      return _validationError(
        'execute_script',
        'Invalid "language": expected one of ${supportedLanguages.join(', ')}.',
      );
    }

    final code = parameters['code'];
    if (code is! String || code.trim().isEmpty) {
      return _validationError(
        'execute_script',
        'Missing or invalid "code". Provide the script source to execute.',
      );
    }

    final env = _parseEnv(parameters['env']);
    if (env == null) {
      return _validationError(
        'execute_script',
        'Invalid "env": expected a map of string keys to string values.',
      );
    }

    final rawTimeout = parameters['timeoutSeconds'] ?? 30;
    if (rawTimeout is! int || rawTimeout < 1 || rawTimeout > 120) {
      return _validationError(
        'execute_script',
        'Invalid "timeoutSeconds": expected an integer between 1 and 120.',
      );
    }

    try {
      final provider = await runnerProviderFactory();
      if (provider == null) {
        return SystemResponse.error(
          command: 'execute_script',
          errorMessage:
              'No external runner is configured. Add a runner endpoint in Settings to execute scripts.',
        );
      }

      final result = await provider.executeScript(
        language: language,
        code: code,
        env: env.isEmpty ? null : env,
        timeoutSeconds: rawTimeout,
      );

      return SystemResponse.success(
        command: 'execute_script',
        data: result.toJson(),
      );
    } on TimeoutException {
      return SystemResponse.error(
        command: 'execute_script',
        errorMessage: 'Runner timed out after ${rawTimeout}s.',
      );
    } on RunnerException catch (e) {
      return SystemResponse.error(
        command: 'execute_script',
        errorMessage: e.message,
      );
    } catch (e) {
      return SystemResponse.error(
        command: 'execute_script',
        errorMessage: 'Script execution failed: $e',
      );
    }
  }

  /// Converts a loosely typed `env` map into string pairs, or null if invalid.
  Map<String, String>? _parseEnv(dynamic raw) {
    if (raw == null) return const {};
    if (raw is! Map) return null;

    final parsed = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.value is! String && entry.value != null) return null;
      parsed[entry.key.toString()] = (entry.value ?? '').toString();
    }
    return parsed;
  }

  /// Builds a structured validation error response.
  SystemResponse _validationError(String command, String message) {
    return SystemResponse.error(
      command: command,
      errorMessage: 'Validation error for $command: $message',
    );
  }
}
