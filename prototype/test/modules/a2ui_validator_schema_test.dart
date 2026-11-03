import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/a2ui/a2ui_validator.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_component_registry.dart';

Map<String, dynamic> surface(List<Map<String, dynamic>> components) {
  return {
    'messages': [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'main',
          'catalogId': 'basic/v1',
          'components': components,
        },
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A2UIValidator schema validation', () {
    test('accepts a Card with a single child', () {
      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'Card', 'child': 'text_1'},
        {'id': 'text_1', 'component': 'Text', 'text': 'Hello'},
      ]));

      expect(result.isValid, isTrue);
    });

    test('rejects a Card that uses children instead of child', () {
      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'Card', 'children': ['col_1']},
        {
          'id': 'col_1',
          'component': 'Column',
          'children': ['text_1'],
        },
        {'id': 'text_1', 'component': 'Text', 'text': 'Hello'},
      ]));

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('child'));
      expect(result.errorMessage, contains('children'));
    });

    test('rejects containers without their required children list', () {
      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'Row'},
      ]));

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('children'));
    });

    test('rejects references to missing components', () {
      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'Card', 'child': 'missing'},
      ]));

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('missing component "missing"'));
    });

    test('rejects unknown properties on known components', () {
      final result = A2UIValidator.validate(surface([
        {
          'id': 'root',
          'component': 'Text',
          'text': 'Hello',
          'bogusProperty': true,
        },
      ]));

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('bogusProperty'));
      expect(result.errorMessage, contains('not allowed'));
    });

    test('rejects unknown component types', () {
      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'MadeUpWidget'},
      ]));

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Unknown component type'));
    });

    test('allows custom components registered at runtime', () {
      A2UIComponentRegistry.instance.register(
        'CustomBadge',
        (context, ctx) => const SizedBox.shrink(),
      );

      final result = A2UIValidator.validate(surface([
        {'id': 'root', 'component': 'CustomBadge', 'label': 'New'},
      ]));

      expect(result.isValid, isTrue);
    });
  });
}
