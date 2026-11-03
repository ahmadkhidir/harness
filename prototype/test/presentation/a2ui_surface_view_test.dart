import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_audio_player.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_video_player.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_component_registry.dart';
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

    testWidgets('renders official GitHub spec with components directly in createSurface', (tester) async {
      final officialPayload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {
              'surfaceId': 'official_form',
              'catalogId': 'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
              'components': [
                {
                  'id': 'root',
                  'component': 'Column',
                  'children': ['name_input', 'agree_check'],
                },
                {
                  'id': 'name_input',
                  'component': 'TextField',
                  'label': 'Representative',
                  'placeholder': 'Enter name',
                  'value': '\${/form/rep}',
                },
                {
                  'id': 'agree_check',
                  'component': 'CheckBox',
                  'label': 'I agree to the terms',
                  'value': true,
                },
              ],
              'dataModel': {
                'form': {'rep': 'John Doe'},
              },
            },
          },
        ],
      };

      await tester.pumpWidget(buildTestWidget(payload: officialPayload));
      await tester.pumpAndSettle();

      expect(find.text('Representative'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('I agree to the terms'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('supports dynamic custom component registration via A2UIComponentRegistry', (tester) async {
      // Register custom component
      A2UIComponentRegistry.instance.register('CustomMetricBadge', (context, ctx) {
        final label = ctx.properties['label']?.toString() ?? '';
        final value = ctx.resolveBinding(ctx.properties['value'])?.toString() ?? '';
        return Container(
          key: const Key('custom_metric_badge'),
          padding: const EdgeInsets.all(8),
          color: Colors.blue.shade100,
          child: Text('$label: $value'),
        );
      });

      final customPayload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {
              'surfaceId': 'custom_surf',
              'components': [
                {
                  'id': 'root',
                  'component': 'CustomMetricBadge',
                  'label': 'GDP Growth',
                  'value': '\${/gdp/growth}',
                },
              ],
              'dataModel': {
                'gdp': {'growth': '+4.2%'},
              },
            },
          },
        ],
      };

      await tester.pumpWidget(buildTestWidget(payload: customPayload));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom_metric_badge')), findsOneWidget);
      expect(find.text('GDP Growth: +4.2%'), findsOneWidget);
    });

    testWidgets('renders components specified as an ID-to-component Map dictionary', (tester) async {
      final mapPayload = {
        'messages': [
          {
            'createSurface': {
              'surfaceId': 'null', // Malformed surfaceId string "null"
              'catalogId': 'basic/v1',
              'components': {
                'root': {
                  'component': 'Card',
                  'child': 'text_1',
                },
                'text_1': {
                  'component': 'Text',
                  'text': 'Rendered from Map Dictionary',
                  'variant': 'title',
                },
              },
            },
          },
        ],
      };

      await tester.pumpWidget(buildTestWidget(payload: mapPayload));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Rendered from Map Dictionary'), findsOneWidget);
      expect(find.textContaining('A2UI notice:'), findsNothing);
    });

    testWidgets('renders flat createSurface payload without messages wrapper array', (tester) async {
      final flatPayload = {
        'createSurface': {
          'surfaceId': 'flat_surface',
          'components': [
            {
              'id': 'root',
              'component': {'Text': {'text': 'Flat Payload Rendered'}},
            },
          ],
        },
      };

      await tester.pumpWidget(buildTestWidget(payload: flatPayload));
      await tester.pumpAndSettle();

      expect(find.text('Flat Payload Rendered'), findsOneWidget);
      expect(find.textContaining('A2UI notice:'), findsNothing);
    });

    testWidgets('Row automatically wraps in horizontal SingleChildScrollView to prevent overflow', (tester) async {
      // Place a wide Row with 5 items inside a constrained 300px box
      final wideRowPayload = {
        'createSurface': {
          'surfaceId': 'wide_row_surface',
          'components': [
            {
              'id': 'root',
              'component': 'Row',
              'children': ['item_1', 'item_2', 'item_3', 'item_4', 'item_5'],
            },
            {
              'id': 'item_1',
              'component': 'Text',
              'text': 'Item 1 - Very Long Description That Exceeds Width',
            },
            {
              'id': 'item_2',
              'component': 'Text',
              'text': 'Item 2 - Very Long Description That Exceeds Width',
            },
            {
              'id': 'item_3',
              'component': 'Text',
              'text': 'Item 3 - Very Long Description That Exceeds Width',
            },
            {
              'id': 'item_4',
              'component': 'Text',
              'text': 'Item 4 - Very Long Description That Exceeds Width',
            },
            {
              'id': 'item_5',
              'component': 'Text',
              'text': 'Item 5 - Very Long Description That Exceeds Width',
            },
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: A2UISurfaceView(payload: wideRowPayload),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Row is rendered without any RenderFlex overflow exception
      expect(find.byType(Row), findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.scrollDirection, equals(Axis.horizontal));
      expect(find.textContaining('Item 1'), findsOneWidget);
    });

    testWidgets('renders AudioPlayer component with title, playback controls and timeline slider', (tester) async {
      final audioPayload = {
        'createSurface': {
          'surfaceId': 'audio_surface',
          'components': [
            {
              'id': 'root',
              'component': 'AudioPlayer',
              'url': 'https://example.com/audio/sample.mp3',
              'title': 'Podcast Episode 1',
              'autoPlay': false,
            },
          ],
        },
      };

      await tester.pumpWidget(buildTestWidget(payload: audioPayload));
      await tester.pumpAndSettle();

      expect(find.byType(A2UIAudioPlayer), findsOneWidget);
      expect(find.text('Podcast Episode 1'), findsOneWidget);
      expect(find.byKey(const Key('audio_play_pause_button')), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('renders Video component with preview fallback or player controls', (tester) async {
      final videoPayload = {
        'createSurface': {
          'surfaceId': 'video_surface',
          'components': [
            {
              'id': 'root',
              'component': 'Video',
              'url': 'https://example.com/video/stream.mp4',
              'autoPlay': false,
              'controls': true,
            },
          ],
        },
      };

      await tester.pumpWidget(buildTestWidget(payload: videoPayload));
      await tester.pumpAndSettle();

      expect(find.byType(A2UIVideoPlayer), findsOneWidget);
      // In headless unit tests without video codecs, the component gracefully renders its fallback or player UI
      final hasFallback = find.text('Video Preview').evaluate().isNotEmpty;
      final hasPlayer = find.byType(AspectRatio).evaluate().isNotEmpty;
      expect(hasFallback || hasPlayer, isTrue);
    });
  });
}

