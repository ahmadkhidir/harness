import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/a2ui/a2ui_module.dart';
import 'package:harness/presentation/widgets/message_bubble.dart';
import 'package:harness/providers/model_provider.dart';

class _ScriptedA2UIProvider extends ModelProvider {
  final List<String> responses;
  int _index = 0;

  _ScriptedA2UIProvider({required this.responses});

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted_a2ui',
        providerType: 'gemini',
        displayName: 'Scripted A2UI Model',
        modelName: 'scripted-1',
        isActive: true,
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    if (_index < responses.length) {
      return responses[_index++];
    }
    return responses.last;
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fs;
  late AppDatabase db;
  late SessionService sessionService;
  late CommandRouter router;
  late A2UIModule a2uiModule;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('feat_006_acceptance_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
    db = AppDatabase.inMemory();
    sessionService = SessionService(fileSystem: fs, database: db);

    router = CommandRouter();
    a2uiModule = A2UIModule();
    router.registerModule(a2uiModule);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('FEAT-006 Acceptance Tests - Declarative A2UI Surface Rendering & On-Demand Catalog', () {
    test('Criterion 1: Agent invokes load_a2ui_catalog(catalog: "basic/v1"), schemas returned in observation and evicted afterward', () async {
      // Step 1: LLM calls load_a2ui_catalog to inspect available components
      // Step 2: LLM receives observation and emits final send_a2ui
      final provider = _ScriptedA2UIProvider(responses: [
        '<system_call>{"command": "load_a2ui_catalog", "parameters": {"catalog": "basic/v1"}}</system_call>',
        '<system_call>{"command": "send_a2ui", "parameters": {"messages": [{"version": "1.0", "createSurface": {"surfaceId": "card_01", "catalogId": "basic/v1"}}, {"version": "1.0", "updateComponents": {"surfaceId": "card_01", "components": [{"id": "root", "type": "Text", "properties": {"text": "UI Loaded"}}]}}]}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine.executeTurn(
        userPrompt: 'Show me an interactive card',
        sessionId: 'sess_test',
      ).toList();

      // Verify load_a2ui_catalog was started and finished
      expect(events.any((e) => e is EngineSystemCallStarted && e.call.command == 'load_a2ui_catalog'), isTrue);
      expect(events.any((e) => e is EngineSystemCallFinished && e.call.command == 'load_a2ui_catalog' && e.response.isSuccess), isTrue);

      // Verify final delivery is a turn with A2UI content
      final completedEvent = events.firstWhere((e) => e is EngineTurnCompleted) as EngineTurnCompleted;
      expect(completedEvent.turn.contentType, equals('a2ui'));
      expect(completedEvent.turn.a2uiSurfaceId, equals('card_01'));
      expect(completedEvent.turn.a2uiPayload, isNotNull);

      // Eviction check: Verify next turn's baseline system instruction does NOT contain the full catalog schemas
      final nextTurnInstruction = ContextBuilder().buildSystemInstruction(
        commands: router.allCommandDefinitions,
        storageTree: '<filesystem>\nprimary/\n</filesystem>',
        availableSkills: const [],
      );
      // Catalog documentation is transient and not baked into the baseline prompt
      expect(nextTurnInstruction.contains('A2UI Catalog: basic/v1'), isFalse);
    });

    testWidgets('Criterion 2 & 3: Valid A2UI messages render matching Flutter widgets and bind dynamic @path data', (tester) async {
      final a2uiPayload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {'surfaceId': 'hotel_res', 'catalogId': 'basic/v1'},
          },
          {
            'version': '1.0',
            'updateDataModel': {
              'surfaceId': 'hotel_res',
              'value': {
                'hotelName': 'Grand Alpine Resort',
                'bookingStatus': 'Confirmed',
                'nights': 3,
              },
            },
          },
          {
            'version': '1.0',
            'updateComponents': {
              'surfaceId': 'hotel_res',
              'components': [
                {
                  'id': 'root',
                  'type': 'Card',
                  'properties': {'child': 'content_col', 'elevation': 3},
                },
                {
                  'id': 'content_col',
                  'type': 'Column',
                  'properties': {
                    'children': ['hotel_text', 'status_row', 'confirm_btn'],
                  },
                },
                {
                  'id': 'hotel_text',
                  'type': 'Text',
                  'properties': {
                    'text': {'@path': '/hotelName'},
                    'style': 'title',
                    'fontWeight': 'bold',
                  },
                },
                {
                  'id': 'status_row',
                  'type': 'Row',
                  'properties': {
                    'children': ['status_icon', 'status_text'],
                  },
                },
                {
                  'id': 'status_icon',
                  'type': 'Icon',
                  'properties': {'icon': 'check_circle', 'color': 'success'},
                },
                {
                  'id': 'status_text',
                  'type': 'Text',
                  'properties': {
                    'text': {'@path': '/bookingStatus'},
                    'color': 'success',
                  },
                },
                {
                  'id': 'confirm_btn',
                  'type': 'Button',
                  'properties': {
                    'label': 'View Reservation',
                    'action': 'view_reservation',
                    'style': 'filled',
                  },
                },
              ],
            },
          },
        ],
      };

      final turn = Turn(
        id: 'turn_hotel_1',
        sessionId: 'sess_1',
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'a2ui',
        text: 'Your reservation is ready:',
        a2uiSurfaceId: 'hotel_res',
        a2uiPayload: a2uiPayload,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(turn: turn),
        ),
      ));
      await tester.pumpAndSettle();

      // Companion text is rendered
      expect(find.text('Your reservation is ready:'), findsOneWidget);

      // Native Flutter widgets compiled from A2UI specification
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Grand Alpine Resort'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'View Reservation'), findsOneWidget);
    });

    testWidgets('Criterion 4: Pure A2UI dispatch with no accompanying text displays only the clean card with zero preamble', (tester) async {
      final a2uiPayload = {
        'messages': [
          {
            'version': '1.0',
            'createSurface': {'surfaceId': 'quick_confirm', 'catalogId': 'basic/v1'},
          },
          {
            'version': '1.0',
            'updateComponents': {
              'surfaceId': 'quick_confirm',
              'components': [
                {
                  'id': 'root',
                  'type': 'Card',
                  'properties': {'child': 'btn_proceed'},
                },
                {
                  'id': 'btn_proceed',
                  'type': 'Button',
                  'properties': {'label': 'Authorize Transaction', 'action': 'auth_tx'},
                },
              ],
            },
          },
        ],
      };

      final pureTurn = Turn(
        id: 'turn_pure_1',
        sessionId: 'sess_1',
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'a2ui',
        text: null, // Pure A2UI with NO accompanying text
        a2uiSurfaceId: 'quick_confirm',
        a2uiPayload: a2uiPayload,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(turn: pureTurn),
        ),
      ));
      await tester.pumpAndSettle();

      // Only the card is rendered
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Authorize Transaction'), findsOneWidget);
      // No preamble or filler text
      expect(find.text('Here is your widget:'), findsNothing);
      expect(find.text('Certainly!'), findsNothing);
    });

    testWidgets('Edge Case 1: Malformed A2UI JSON payload displays fallback notice without crashing UI isolate', (tester) async {
      final malformedTurn = Turn(
        id: 'turn_malformed',
        sessionId: 'sess_1',
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'a2ui',
        text: 'Encountered layout error',
        a2uiPayload: {
          'messages': [
            // Malformed messages missing valid surface and component structures
            {'corruptField': 12345},
          ],
        },
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(turn: malformedTurn),
        ),
      ));
      await tester.pumpAndSettle();

      // The UI isolate continues functioning and displays a graceful fallback notice
      expect(find.text('Encountered layout error'), findsOneWidget);
      expect(find.textContaining('A2UI notice:'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Edge Case 2: Missing required component properties apply safe defaults according to basic/v1 schema', (tester) async {
      final sparseTurn = Turn(
        id: 'turn_sparse',
        sessionId: 'sess_1',
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'a2ui',
        a2uiPayload: {
          'messages': [
            {
              'version': '1.0',
              'createSurface': {'surfaceId': 'sparse_surf', 'catalogId': 'basic/v1'},
            },
            {
              'version': '1.0',
              'updateComponents': {
                'surfaceId': 'sparse_surf',
                'components': [
                  {
                    'id': 'root',
                    'type': 'Column',
                    'properties': {
                      'children': ['txt_empty', 'btn_empty', 'icon_empty', 'div_empty'],
                    },
                  },
                  {'id': 'txt_empty', 'type': 'Text'},
                  {'id': 'btn_empty', 'type': 'Button'},
                  {'id': 'icon_empty', 'type': 'Icon'},
                  {'id': 'div_empty', 'type': 'Divider'},
                ],
              },
            },
          ],
        },
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(turn: sparseTurn),
        ),
      ));
      await tester.pumpAndSettle();

      // Renders with safe default values (default label 'Action', default icon 'info', Divider)
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });
}
