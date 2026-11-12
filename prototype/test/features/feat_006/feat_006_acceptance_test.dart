import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/modules/a2ui/a2ui_surface_store.dart';
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
    if (_index < responses.length) return responses[_index++];
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

String a2uiDelivery(String surfaceId, List<Map<String, dynamic>> messages) {
  return '<system_call>{"command": "send_ui_message", "parameters": '
      '{"message": {"a2ui": ${_json(messages)}}}}</system_call>';
}

String _json(Object value) {
  // Tiny JSON encoder for test payloads without importing dart:convert.
  if (value is String) return '"${value.replaceAll('"', r'\"')}"';
  if (value is num || value is bool) return '$value';
  if (value is List) return '[${value.map((item) => _json(item)).join(',')}]';
  if (value is Map) {
    return '{${value.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')}}';
  }
  return 'null';
}

Turn a2uiTurn({
  required String surfaceId,
  required Map<String, dynamic> payload,
  String? text,
}) {
  return Turn(
    id: 'turn_$surfaceId',
    sessionId: 'sess_1',
    timestamp: DateTime.now().toUtc(),
    sender: 'agent',
    contentType: 'a2ui',
    text: text,
    a2uiSurfaceId: surfaceId,
    a2uiPayload: payload,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CommandRouter router;

  setUp(() {
    router = CommandRouter();
  });

  group('FEAT-006 Acceptance Tests - A2UI v1 Surfaces', () {
    test('send_ui_message creates a surface and stores it', () async {
      final provider = _ScriptedA2UIProvider(responses: [
        a2uiDelivery('main', [
          {
            'version': '1.0',
            'createSurface': {
              'surfaceId': 'main',
              'catalogId': 'basic/v1',
              'components': [
                {'id': 'root', 'component': 'Card', 'child': 'title'},
                {'id': 'title', 'component': 'Text', 'text': 'Hello'},
              ],
            },
          },
        ]),
      ]);
      final store = A2UISurfaceStore();
      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(
            userPrompt: 'Show a card',
            sessionId: 'sess_test',
            surfaceStore: store,
          )
          .toList();

      final completed =
          events.firstWhere((e) => e is EngineTurnCompleted) as EngineTurnCompleted;
      expect(completed.turn.contentType, 'a2ui');
      expect(completed.turn.a2uiSurfaceId, 'main');
      expect(store.surface('main'), isNotNull);
      expect(store.surface('main')!.components['title']!['text'], 'Hello');
    });

    test('send_ui_message updates an existing surface in place', () async {
      final provider = _ScriptedA2UIProvider(responses: [
        a2uiDelivery('main', [
          {
            'version': '1.0',
            'createSurface': {
              'surfaceId': 'main',
              'catalogId': 'basic/v1',
              'components': [
                {'id': 'root', 'component': 'Card', 'child': 'title'},
                {'id': 'title', 'component': 'Text', 'text': 'Old'},
              ],
            },
          },
        ]),
        a2uiDelivery('main', [
          {
            'version': '1.0',
            'updateComponents': {
              'surfaceId': 'main',
              'components': [
                {'id': 'title', 'component': 'Text', 'text': 'New'},
              ],
            },
          },
        ]),
      ]);
      final store = A2UISurfaceStore();
      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      await engine
          .executeTurn(
            userPrompt: 'Create',
            sessionId: 'sess_test',
            surfaceStore: store,
          )
          .toList();
      await engine
          .executeTurn(
            userPrompt: 'Update',
            sessionId: 'sess_test',
            surfaceStore: store,
          )
          .toList();

      expect(store.surface('main')!.components['title']!['text'], 'New');
      expect(store.surface('main')!.components['root']!['component'], 'Card');
    });

    test('send_ui_message deletes a surface', () async {
      final provider = _ScriptedA2UIProvider(responses: [
        a2uiDelivery('main', [
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
        ]),
        a2uiDelivery('main', [
          {
            'version': '1.0',
            'deleteSurface': {'surfaceId': 'main'},
          },
        ]),
      ]);
      final store = A2UISurfaceStore();
      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      await engine
          .executeTurn(
            userPrompt: 'Create',
            sessionId: 'sess_test',
            surfaceStore: store,
          )
          .toList();
      await engine
          .executeTurn(
            userPrompt: 'Delete',
            sessionId: 'sess_test',
            surfaceStore: store,
          )
          .toList();

      expect(store.surface('main'), isNull);
    });

    test('send_ui_message with a string message delivers text', () async {
      final provider = _ScriptedA2UIProvider(responses: [
        '<system_call>{"command": "send_ui_message", "parameters": '
        '{"message": "Plain text reply"}}</system_call>',
      ]);
      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(userPrompt: 'Hello', sessionId: 'sess_test')
          .toList();
      final completed =
          events.firstWhere((e) => e is EngineTurnCompleted) as EngineTurnCompleted;
      expect(completed.turn.contentType, 'text');
      expect(completed.turn.text, 'Plain text reply');
    });

    testWidgets('renders a live surface in place without companion text',
        (tester) async {
      final store = A2UISurfaceStore();
      store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
            'components': [
              {'id': 'root', 'component': 'Card', 'child': 'title'},
              {'id': 'title', 'component': 'Text', 'text': 'Before'},
            ],
          },
        },
      ]);

      final turn = a2uiTurn(
        surfaceId: 'main',
        payload: const {'messages': []},
        text: 'Companion text',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            turn: turn,
            a2uiSurface: store.surface('main'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Companion text'), findsNothing);
      expect(find.text('Before'), findsOneWidget);

      store.applyMessages([
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'main',
            'components': [
              {'id': 'title', 'component': 'Text', 'text': 'After'},
            ],
          },
        },
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            turn: turn,
            a2uiSurface: store.surface('main'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Before'), findsNothing);
    });

    testWidgets('omits a component whose child has not arrived yet',
        (tester) async {
      final store = A2UISurfaceStore();
      store.applyMessages([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'main',
            'catalogId': 'basic/v1',
            'components': [
              {'id': 'root', 'component': 'Card', 'child': 'missing'},
            ],
          },
        },
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            turn: a2uiTurn(
              surfaceId: 'main',
              payload: const {'messages': []},
            ),
            a2uiSurface: store.surface('main'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('A2UI notice'), findsNothing);
    });
  });
}
