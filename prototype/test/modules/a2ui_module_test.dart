import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/a2ui/a2ui_module.dart';
import 'package:harness/modules/a2ui/catalogs/basic_v1_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late A2UIModule a2ui;

  setUp(() {
    a2ui = A2UIModule();
  });

  group('A2UIModule & Catalog Tests', () {
    test('exposes load_a2ui_catalog and send_a2ui commands in module catalog', () {
      expect(a2ui.moduleName, equals('a2ui'));
      final cmdNames = a2ui.commands.map((c) => c.command).toList();
      expect(cmdNames, containsAll(['load_a2ui_catalog', 'send_a2ui']));
    });

    test('load_a2ui_catalog returns documentation for basic/v1', () async {
      final response = await a2ui.executeCommand('load_a2ui_catalog', {
        'catalog': 'basic/v1',
      });

      expect(response.isSuccess, isTrue);
      expect(response.data, contains('A2UI Catalog: basic/v1'));
      expect(response.data, contains('Card'));
      expect(response.data, contains('Column'));
      expect(response.data, contains('Row'));
      expect(response.data, contains('Text'));
      expect(response.data, contains('Icon'));
      expect(response.data, contains('Button'));
      expect(response.data, contains('Divider'));
    });

    test('load_a2ui_catalog returns structured error for unsupported catalog', () async {
      final response = await a2ui.executeCommand('load_a2ui_catalog', {
        'catalog': 'advanced/v9',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Unsupported catalog "advanced/v9"'));
      expect(response.errorMessage, contains('basic/v1'));
    });

    test('send_a2ui validates presence of messages parameter', () async {
      final invalidResponse = await a2ui.executeCommand('send_a2ui', {
        'messages': [],
      });
      expect(invalidResponse.isError, isTrue);
      expect(invalidResponse.errorMessage, contains('Invalid or missing "messages" list'));

      final validResponse = await a2ui.executeCommand('send_a2ui', {
        'messages': [
          {'version': '1.0', 'createSurface': {'surfaceId': 'test', 'catalogId': 'basic/v1'}},
        ],
      });
      expect(validResponse.isSuccess, isTrue);
    });

    test('JsonPointerResolver traverses nested maps and lists', () {
      final dataModel = {
        'title': 'Confirmation',
        'details': {
          'flight': 'AA 404',
          'seats': ['12A', '12B'],
        },
        'escaped/key': 'Special Value',
      };

      // Top-level
      expect(JsonPointerResolver.resolvePointer('/title', dataModel), equals('Confirmation'));

      // Nested map
      expect(JsonPointerResolver.resolvePointer('/details/flight', dataModel), equals('AA 404'));

      // List indexing
      expect(JsonPointerResolver.resolvePointer('/details/seats/0', dataModel), equals('12A'));
      expect(JsonPointerResolver.resolvePointer('/details/seats/1', dataModel), equals('12B'));

      // RFC 6901 escape handling (~1 for /)
      expect(JsonPointerResolver.resolvePointer('/escaped~1key', dataModel), equals('Special Value'));

      // Missing path
      expect(JsonPointerResolver.resolvePointer('/details/missing', dataModel), isNull);
    });

    test('JsonPointerResolver resolves both Map and String @path syntax', () {
      final dataModel = {'status': 'Confirmed', 'priority': 'High'};

      // Map syntax: {"@path": "/status"}
      expect(JsonPointerResolver.resolve({'@path': '/status'}, dataModel), equals('Confirmed'));

      // String syntax: "@path: /priority"
      expect(JsonPointerResolver.resolve('@path: /priority', dataModel), equals('High'));

      // Literal pass-through
      expect(JsonPointerResolver.resolve('Plain Literal Text', dataModel), equals('Plain Literal Text'));
      expect(JsonPointerResolver.resolve(42, dataModel), equals(42));
    });
  });
}
