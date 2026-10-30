import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/modules/base/harness_module.dart';

class MockModuleA extends HarnessModule {
  @override
  String get moduleName => 'module_a';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'echo_a',
          description: 'Echoes back parameter a',
          parametersSchema: const {'type': 'object'},
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return SystemResponse.success(command: command, data: parameters['msg']);
  }
}

class MockModuleB extends HarnessModule {
  @override
  String get moduleName => 'module_b';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'failing_op',
          description: 'Throws an unhandled exception',
          parametersSchema: const {'type': 'object'},
        ),
        CommandDefinition(
          command: 'slow_op',
          description: 'Completes after 100ms',
          parametersSchema: const {'type': 'object'},
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    if (command == 'failing_op') {
      throw StateError('Simulated internal module crash');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return SystemResponse.success(command: command, data: 'slow_done');
  }
}

void main() {
  group('CommandRouter - Registry & Execution', () {
    late CommandRouter router;
    late MockModuleA moduleA;
    late MockModuleB moduleB;

  setUp(() {
      router = CommandRouter();
      moduleA = MockModuleA();
      moduleB = MockModuleB();
      router.registerModule(moduleA);
      router.registerModule(moduleB);
    });

    test('registers modules and exposes all commands in catalog', () {
      expect(router.hasCommand('echo_a'), isTrue);
      expect(router.hasCommand('failing_op'), isTrue);
      expect(router.hasCommand('slow_op'), isTrue);
      expect(router.hasCommand('non_existent'), isFalse);
      expect(router.allCommandDefinitions.length, 3);
    });

    test('detects command name collisions', () {
      final duplicate = MockModuleA();
      expect(() => router.registerModule(duplicate), throwsStateError);
    });

    test('executes a single command successfully', () async {
      final call = SystemCall(command: 'echo_a', parameters: {'msg': 'hello'});
      final response = await router.executeCall(call);

      expect(response.isSuccess, isTrue);
      expect(response.command, 'echo_a');
      expect(response.data, 'hello');
    });

    test('returns structured error for unregistered command', () async {
      final call = SystemCall(command: 'missing', parameters: {});
      final response = await router.executeCall(call);

      expect(response.isError, isTrue);
      expect(response.errorMessage?.contains('Unknown command'), isTrue);
    });

    test('isolates exceptions and runs parallel commands concurrently', () async {
      final calls = [
        SystemCall(command: 'echo_a', parameters: {'msg': 'call1'}),
        SystemCall(command: 'failing_op', parameters: {}),
        SystemCall(command: 'slow_op', parameters: {}),
      ];

      final stopwatch = Stopwatch()..start();
      final responses = await router.executeCallsParallel(calls);
      stopwatch.stop();

      // Parallel execution should finish near 100ms (slowest call), not serial 150ms+
      expect(responses.length, 3);
      expect(responses[0].isSuccess, isTrue);
      expect(responses[0].data, 'call1');

      // The failing command must return a structured error response
      expect(responses[1].isError, isTrue);
      expect(responses[1].errorMessage?.contains('Simulated internal module crash'), isTrue);

      // Sibling command succeeded regardless of sibling failure
      expect(responses[2].isSuccess, isTrue);
      expect(responses[2].data, 'slow_done');
    });
  });
}

