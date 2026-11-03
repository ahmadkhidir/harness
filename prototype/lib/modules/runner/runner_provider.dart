/// Structured execution outcome returned by an external script runner.
class ScriptExecutionResult {
  /// The process exit code (0 for success).
  final int exitCode;

  /// Standard output captured during execution.
  final String stdout;

  /// Standard error captured during execution.
  final String stderr;

  /// Execution duration in milliseconds.
  final int executionTimeMs;

  const ScriptExecutionResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.executionTimeMs,
  });

  /// Converts the result to a JSON map.
  Map<String, dynamic> toJson() => {
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'executionTimeMs': executionTimeMs,
      };
}

/// Failure raised by an external runner bridge.
class RunnerException implements Exception {
  /// Human- and model-readable failure description.
  final String message;

  /// HTTP status code when the failure originated from a runner response.
  final int? statusCode;

  const RunnerException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Abstract contract for offloading arbitrary code execution to an isolated external environment.
///
/// Implements App Store Review Guideline 2.5.2 compliance by ensuring no dynamic
/// interpreted code is compiled or executed directly inside the mobile app process.
abstract class RunnerProvider {
  /// Executes a script in a sandboxed microVM/container and returns stdout/stderr.
  Future<ScriptExecutionResult> executeScript({
    required String language,
    required String code,
    Map<String, String>? env,
    int timeoutSeconds = 30,
  });
}
