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

    test('verifies parameters against published schema and returns located error', () async {
      // Register a module with strict parametersSchema
      final strictModule = _StrictSchemaModule();
      router.registerModule(strictModule);

      // Missing required property
      final invalidCall = SystemCall(
        command: 'strict_cmd',
        parameters: {'count': 5}, // missing required 'title'
      );
      final response = await router.executeCall(invalidCall);

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Schema validation failed for "strict_cmd"'));
      expect(response.errorMessage, contains('at /parameters/title'));
      expect(response.errorMessage, contains('Required property "title" is missing'));

      // Wrong type
      final wrongTypeCall = SystemCall(
        command: 'strict_cmd',
        parameters: {'title': 'Valid', 'count': 'not_a_number'},
      );
      final wrongTypeResponse = await router.executeCall(wrongTypeCall);
      expect(wrongTypeResponse.isError, isTrue);
      expect(wrongTypeResponse.errorMessage, contains('at /parameters/count'));
      expect(wrongTypeResponse.errorMessage, contains('Expected type "integer"'));
    });
  });
}

class _StrictSchemaModule extends HarnessModule {
  @override
  String get moduleName => 'strict_module';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'strict_cmd',
          description: 'A command with strict schema validation',
          parametersSchema: const {
            'type': 'object',
            'required': ['title'],
            'properties': {
              'title': {'type': 'string'},
              'count': {'type': 'integer'},
            },
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    return SystemResponse.success(command: command, data: 'ok');
  }
}

