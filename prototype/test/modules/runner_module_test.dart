import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/runner/runner_module.dart';
import 'package:harness/modules/runner/runner_provider.dart';

import '../mocks/fake_bridges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRunnerProvider runner;
  late RunnerModule module;

  setUp(() {
    runner = FakeRunnerProvider(
      result: const ScriptExecutionResult(
        exitCode: 0,
        stdout: '2**100 result',
        stderr: '',
        executionTimeMs: 42,
      ),
    );
    module = RunnerModule(runnerProviderFactory: () async => runner);
  });

  group('RunnerModule - FEAT-008', () {
    test('execute_script returns stdout, stderr, and exit code', () async {
      final response = await module.executeCommand('execute_script', {
        'language': 'python',
        'code': 'print(2**100)',
        'env': {'MODE': 'test'},
        'timeoutSeconds': 15,
      });

      expect(response.isSuccess, isTrue);
      expect(runner.lastLanguage, 'python');
      expect(runner.lastCode, 'print(2**100)');
      expect(runner.lastEnv, {'MODE': 'test'});
      expect(runner.lastTimeoutSeconds, 15);

      final data = response.data as Map<String, dynamic>;
      expect(data['exitCode'], 0);
      expect(data['stdout'], '2**100 result');
    });

    test('execute_script uses the default 30s timeout', () async {
      final response = await module.executeCommand('execute_script', {
        'language': 'bash',
        'code': 'echo hi',
      });

      expect(response.isSuccess, isTrue);
      expect(runner.lastTimeoutSeconds, 30);
      expect(runner.lastEnv, isNull);
    });

    test('execute_script rejects unsupported languages', () async {
      final response = await module.executeCommand('execute_script', {
        'language': 'ruby',
        'code': 'puts 1',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('language'));
      expect(runner.lastCode, isNull);
    });

    test('execute_script rejects empty code', () async {
      final response = await module.executeCommand('execute_script', {
        'language': 'python',
        'code': '   ',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('"code"'));
    });

    test('execute_script rejects out-of-range timeouts', () async {
      final response = await module.executeCommand('execute_script', {
        'language': 'python',
        'code': 'print(1)',
        'timeoutSeconds': 500,
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('timeoutSeconds'));
    });

    test('execute_script reports a missing runner configuration', () async {
      final unconfigured = RunnerModule(runnerProviderFactory: () async => null);

      final response = await unconfigured.executeCommand('execute_script', {
        'language': 'python',
        'code': 'print(1)',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('No external runner'));
    });

    test('execute_script surfaces runner timeouts', () async {
      runner.error = TimeoutException('slow');

      final response = await module.executeCommand('execute_script', {
        'language': 'python',
        'code': 'print(1)',
        'timeoutSeconds': 5,
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('timed out after 5s'));
    });

    test('execute_script surfaces non-2xx runner responses', () async {
      runner.error = const RunnerException(
        'Runner responded HTTP 500: boom',
        statusCode: 500,
      );

      final response = await module.executeCommand('execute_script', {
        'language': 'node',
        'code': 'console.log(1)',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('HTTP 500'));
    });
  });
}
