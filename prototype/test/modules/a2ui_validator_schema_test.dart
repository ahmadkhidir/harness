import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/a2ui/a2ui_surface_store.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_component_registry.dart';

A2UIApplyResult apply(
  List<Map<String, dynamic>> components, {
  String surfaceId = 'main',
  Map<String, dynamic>? dataModel,
}) {
  final store = A2UISurfaceStore();
  return store.applyMessages([
    {
      'version': '1.0',
      'createSurface': {
        'surfaceId': surfaceId,
        'catalogId': 'basic/v1',
        'components': components,
        'dataModel': ?dataModel,
      },
    },
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A2UI surface schema validation', () {
    test('accepts a Card with a single child', () {
      final result = apply([
        {'id': 'root', 'component': 'Card', 'child': 'text_1'},
        {'id': 'text_1', 'component': 'Text', 'text': 'Hello'},
      ]);

      expect(result.success, isTrue);
    });

    test('rejects a Card that uses children instead of child', () {
      final result = apply([
        {'id': 'root', 'component': 'Card', 'children': ['col_1']},
        {
          'id': 'col_1',
          'component': 'Column',
          'children': ['text_1'],
        },
        {'id': 'text_1', 'component': 'Text', 'text': 'Hello'},
      ]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('child'));
      expect(result.errorMessage, contains('children'));
    });

    test('rejects containers without their required children list', () {
      final result = apply([
        {'id': 'root', 'component': 'Row'},
      ]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('children'));
    });

    test('allows references to components that arrive later', () {
      final store = A2UISurfaceStore();
      final created = store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
          },
        },
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'main',
            'components': [
              {'id': 'root', 'component': 'Card', 'child': 'title'},
            ],
          },
        },
      ]);

      expect(created.success, isTrue);
      expect(store.surface('main')!.components.containsKey('title'), isFalse);

      final updated = store.applyMessages([
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'main',
            'components': [
              {'id': 'title', 'component': 'Text', 'text': 'Arrived'},
            ],
          },
        },
      ]);

      expect(updated.success, isTrue);
      expect(store.surface('main')!.components['title']!['text'], 'Arrived');
    });

    test('rejects unknown properties on known components', () {
      final result = apply([
        {
          'id': 'root',
          'component': 'Text',
          'text': 'Hello',
          'bogusProperty': true,
        },
      ]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('bogusProperty'));
      expect(result.errorMessage, contains('not allowed'));
    });

    test('rejects unknown component types', () {
      final result = apply([
        {'id': 'root', 'component': 'MadeUpWidget'},
      ]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Unknown component type'));
    });

    test('allows custom components registered at runtime', () {
      A2UIComponentRegistry.instance.register(
        'CustomBadge',
        (context, ctx) => const SizedBox.shrink(),
      );

      final result = apply([
        {'id': 'root', 'component': 'CustomBadge', 'label': 'New'},
      ]);

      expect(result.success, isTrue);
    });

    test('rejects a duplicate createSurface for the same surfaceId', () {
      final store = A2UISurfaceStore();
      final first = store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
          },
        },
      ]);
      expect(first.success, isTrue);

      final second = store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
          },
        },
      ]);
      expect(second.success, isFalse);
      expect(second.errorMessage, contains('INTEGRITY_ERROR'));
    });

    test('updateComponents upserts by component id', () {
      final store = A2UISurfaceStore();
      store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'Old'},
            ],
          },
        },
      ]);

      final updated = store.applyMessages([
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'main',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'New'},
            ],
          },
        },
      ]);

      expect(updated.success, isTrue);
      expect(store.surface('main')!.components['root']!['text'], 'New');
    });

    test('updateDataModel applies a JSON Pointer path', () {
      final store = A2UISurfaceStore();
      store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'Hello'},
            ],
          },
        },
        {
          'version': '1.0',
          'updateDataModel': {
            'surfaceId': 'main',
            'path': '/user/name',
            'value': 'Ahmad',
          },
        },
      ]);

      expect(store.surface('main')!.dataModel['user']['name'], 'Ahmad');
    });

    test('deleteSurface removes the surface', () {
      final store = A2UISurfaceStore();
      store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'Hello'},
            ],
          },
        },
      ]);

      final deleted = store.applyMessages([
        {
          'version': '1.0',
          'deleteSurface': {'surfaceId': 'main'},
        },
      ]);

      expect(deleted.success, isTrue);
      expect(store.surface('main'), isNull);
    });
    test('rejects a stateful input with a literal value', () {
      final result = apply([
        {
          'id': 'root',
          'component': 'CheckBox',
          'label': 'Agree',
          'value': true,
          'onChange': 'agreement_changed',
        },
      ]);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('data binding'));
    });

    test('accepts a stateful input bound to a data path', () {
      final result = apply(
        [
          {
            'id': 'root',
            'component': 'CheckBox',
            'label': 'Agree',
            'value': {'@path': '/form/agreed'},
            'onChange': 'agreement_changed',
          },
        ],
        dataModel: {
          'form': {'agreed': false},
        },
      );

      expect(result.success, isTrue);
    });
  });
}
