import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_surface_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    required Map<String, dynamic>? payload,
    void Function(String action, Map<String, dynamic> dataModel)? onAction,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: A2UISurfaceView(
            payload: payload,
            onAction: onAction,
          ),
        ),
      ),
    );
  }

  group('A2UISurfaceView Widget Tests', () {
    testWidgets('renders Card, Column, Text, Icon, Button and Divider components', (tester) async {
      String? tappedAction;
      Map<String, dynamic>? tappedData;

      final payload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {
              'surfaceId': 'test_surface',
              'catalogId': 'basic/v1',
            },
          },
          {
            'version': '1.0',
            'updateDataModel': {
              'surfaceId': 'test_surface',
              'value': {
                'eventTitle': 'Mission Launch',
                'status': 'Go for Launch',
              },
            },
          },
          {
            'version': '1.0',
            'updateComponents': {
              'surfaceId': 'test_surface',
              'components': [
                {
                  'id': 'root',
                  'type': 'Card',
                  'properties': {'child': 'main_col'},
                },
                {
                  'id': 'main_col',
                  'type': 'Column',
                  'properties': {
                    'children': ['icon_status', 'title_text', 'sep', 'status_text', 'btn_confirm'],
                  },
                },
                {
                  'id': 'icon_status',
                  'type': 'Icon',
                  'properties': {'icon': 'check_circle', 'color': 'success'},
                },
                {
                  'id': 'title_text',
                  'type': 'Text',
                  'properties': {
                    'text': {'@path': '/eventTitle'},
                    'style': 'title',
                    'fontWeight': 'bold',
                  },
                },
                {
                  'id': 'sep',
                  'type': 'Divider',
                  'properties': {'thickness': 2},
                },
                {
                  'id': 'status_text',
                  'type': 'Text',
                  'properties': {
                    'text': {'@path': '/status'},
                    'style': 'body',
                  },
                },
                {
                  'id': 'btn_confirm',
                  'type': 'Button',
                  'properties': {
                    'label': 'Initiate Ignition',
                    'action': 'ignition_action',
                    'style': 'filled',
                  },
                },
              ],
            },
          },
        ],
      };

      await tester.pumpWidget(buildTestWidget(
        payload: payload,
        onAction: (act, dm) {
          tappedAction = act;
          tappedData = dm;
        },
      ));
      await tester.pumpAndSettle();

      // Check rendered widgets
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Mission Launch'), findsOneWidget);
      expect(find.text('Go for Launch'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Initiate Ignition'), findsOneWidget);

      // Tap button and verify onAction invocation
      await tester.tap(find.text('Initiate Ignition'));
      await tester.pumpAndSettle();

      expect(tappedAction, equals('ignition_action'));
      expect(tappedData?['eventTitle'], equals('Mission Launch'));
    });

    testWidgets('renders fallback notice on malformed payload without crashing isolate', (tester) async {
      final malformedPayload = {
        'messages': 'invalid_string_instead_of_list',
      };

      await tester.pumpWidget(buildTestWidget(payload: malformedPayload));
      await tester.pumpAndSettle();

      expect(find.textContaining('A2UI notice:'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('missing required properties apply safe defaults without throwing', (tester) async {
      final sparsePayload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {'surfaceId': 'sparse_surface', 'catalogId': 'basic/v1'},
          },
          {
            'version': '1.0',
            'updateComponents': {
              'surfaceId': 'sparse_surface',
              'components': [
                {
                  'id': 'root',
                  'type': 'Column',
                  'properties': {
                    'children': ['empty_text', 'empty_btn', 'empty_icon', 'empty_divider'],
                  },
                },
                {
                  'id': 'empty_text',
                  'type': 'Text',
                  // Missing properties
                },
                {
                  'id': 'empty_btn',
                  'type': 'Button',
                  // Missing properties
                },
                {
                  'id': 'empty_icon',
                  'type': 'Icon',
                  // Missing properties
                },
                {
                  'id': 'empty_divider',
                  'type': 'Divider',
                  // Missing properties
                },
              ],
            },
          },
        ],
      };

      await tester.pumpWidget(buildTestWidget(payload: sparsePayload));
      await tester.pumpAndSettle();

      // Should render safely with default text and icons
      expect(find.byType(Column), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Action'), findsOneWidget); // Default button label
      expect(find.byIcon(Icons.info_outline), findsOneWidget); // Default icon
    });
  });
}
