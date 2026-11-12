import 'package:harness/presentation/theme/harness_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/command_definition.dart';
import 'package:harness/core/models/provider_config.dart';
import 'package:harness/core/models/system_call.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/core/routes/app_routes.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/secure_storage/key_storage_service.dart';
import 'package:harness/modules/a2ui/a2ui_surface_store.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_surface_view.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/presentation/bloc/model_switcher_bloc.dart';
import 'package:harness/presentation/bloc/model_switcher_event.dart';
import 'package:harness/presentation/screens/chat_screen.dart';
import 'package:harness/presentation/screens/placeholder_screen.dart';
import 'package:harness/presentation/screens/settings_screen.dart';
import 'package:harness/presentation/widgets/empty_state.dart';
import 'package:harness/presentation/widgets/message_bubble.dart';
import 'package:harness/providers/model_provider.dart';

class MockModelProvider extends ModelProvider {
  final Future<String> Function(List<ModelMessage> messages)? onGenerate;

  MockModelProvider({this.onGenerate});

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'mock_provider',
        providerType: 'local_device',
        displayName: 'Mock Model',
        modelName: 'mock-v1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    if (onGenerate != null) {
      return onGenerate!(messages);
    }
    return '<system_call>\n{"command": "send_ui_message", "parameters": {"message": "I completed the task."}}\n</system_call>';
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield 'Mock model streamed chunk';
  }
}

Widget createTestableChatScreen({
  required HarnessSessionBloc sessionBloc,
  required ModelSwitcherBloc switcherBloc,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<HarnessSessionBloc>.value(value: sessionBloc),
      BlocProvider<ModelSwitcherBloc>.value(value: switcherBloc),
    ],
    child: MaterialApp(
      initialRoute: AppRoutes.chat,
      routes: {
        AppRoutes.chat: (_) => const ChatScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
        AppRoutes.sessions: (_) => const PlaceholderScreen(
              title: 'Sessions Management',
              featureName: 'FEAT-005',
            ),
        AppRoutes.workspace: (_) => const PlaceholderScreen(
              title: 'Workspace',
              featureName: 'FEAT-003 & FEAT-004',
            ),
      },
    ),
  );
}

void main() {
  late AppDatabase database;
  late KeyStorageService keyStorage;
  late HarnessEngine engine;

  setUp(() {
    database = AppDatabase.inMemory();
    keyStorage = KeyStorageService(useInMemoryFallback: true);
    engine = HarnessEngine(
      router: CommandRouter(),
      contextBuilder: ContextBuilder(),
      modelProvider: MockModelProvider(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('ChatScreen initial render displays empty state and app bar elements',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify AppBar widgets
    expect(find.text('Harness'), findsOneWidget);
    expect(find.byIcon(HarnessIcons.sessions), findsOneWidget);
    expect(find.byIcon(HarnessIcons.more), findsOneWidget);

    // Verify empty state is displayed when there are no turns
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Ready for a task'), findsOneWidget);
    expect(find.text('What commands can you execute?'), findsOneWidget);

    // Verify bottom prompt input bar
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(HarnessIcons.send), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Typing slash opens the skill picker sheet', (tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Insert a skill'), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Tapping prompt suggestion chip dispatches user turn',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Tap quick-select suggestion chip
    final chipFinder = find.text('What commands can you execute?');
    expect(chipFinder, findsOneWidget);
    await tester.tap(chipFinder);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Session state should have recorded user turn
    expect(sessionBloc.state.turns.isNotEmpty, isTrue);
    expect(sessionBloc.state.turns.first.text, 'What commands can you execute?');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Submitting text via input bar adds user turn to chat',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Enter prompt into input bar
    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'Write a quick python script');
    await tester.tap(find.byIcon(HarnessIcons.send));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sessionBloc.state.turns.isNotEmpty, isTrue);
    expect(sessionBloc.state.turns.first.text, 'Write a quick python script');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Renders MessageBubble widgets when turns exist in session state',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Initialize with existing turn history
    final userTurn = Turn(
      id: 'turn_user_1',
      sessionId: 'sess_test_1',
      sender: 'user',
      contentType: 'text',
      text: 'Explain quantum computing',
      timestamp: DateTime.now(),
    );
    final agentTurn = Turn(
      id: 'turn_agent_1',
      sessionId: 'sess_test_1',
      sender: 'agent',
      contentType: 'text',
      text: 'Quantum computing leverages superposition and entanglement.',
      timestamp: DateTime.now(),
    );

    sessionBloc.emit(HarnessSessionReady(
      sessionId: 'sess_test_1',
      turns: [userTurn, agentTurn],
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // EmptyState should no longer be rendered
    expect(find.byType(EmptyState), findsNothing);

    // Two message bubbles rendered
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.text('Explain quantum computing'), findsOneWidget);
    expect(find.text('Quantum computing leverages superposition and entanglement.'),
        findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Displays live execution status with collapse button opening tool modal, persisting after turn finishes',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final activeCall = SystemCall(
      command: 'load_skill',
      parameters: const {'skill_name': 'story_writer'},
    );

    sessionBloc.emit(HarnessTurnExecuting(
      sessionId: 'sess_test_1',
      turns: const [],
      statusMessage: 'Executing load_skill...',
      toolIndicators: [
        ToolExecutionIndicator(
          call: activeCall,
          status: 'running',
        ),
      ],
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify live progress spinner, status message, and collapse icon button (NOT the old inline pill)
    expect(find.text('Executing load_skill...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byKey(const ValueKey('executing_tool_calls_button')), findsOneWidget);

    // Verify send button toggled to stop execution button
    expect(find.byIcon(HarnessIcons.stop), findsOneWidget);

    // Tap collapse icon button to open bottom modal sheet during execution
    await tester.tap(find.byKey(const ValueKey('executing_tool_calls_button')));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify modal bottom sheet opens and displays command name, parameters, and running status
    expect(find.text('Tool executions'), findsOneWidget);
    expect(find.text('load_skill'), findsOneWidget);
    expect(find.textContaining('story_writer'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);

    // Close modal
    await tester.tap(find.byIcon(HarnessIcons.x));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Now emit turn completed with the tool execution recorded
    final finishedTurn = Turn(
      id: 'turn_agent_1',
      sessionId: 'sess_test_1',
      timestamp: DateTime.now().toUtc(),
      sender: 'agent',
      contentType: 'text',
      text: 'Story skill loaded successfully!',
      toolCalls: [
        ToolExecutionRecord(
          call: activeCall,
          status: 'success',
          output: 'Skill loaded',
        ),
      ],
    );

    sessionBloc.emit(HarnessSessionReady(
      sessionId: 'sess_test_1',
      turns: [finishedTurn],
    ));
    await tester.pumpAndSettle();

    // Verify the collapse icon button is STILL PRESENT on the turn after finish
    final turnButtonFinder = find.byKey(ValueKey('turn_tool_calls_button_${finishedTurn.id}'));
    expect(turnButtonFinder, findsOneWidget);

    // Tap the icon button on the finished turn
    await tester.tap(turnButtonFinder);
    await tester.pumpAndSettle();

    // Verify modal bottom sheet opens for finished turn showing command and success status
    expect(find.text('Tool executions'), findsOneWidget);
    expect(find.text('load_skill'), findsOneWidget);
    expect(find.textContaining('story_writer'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    expect(find.textContaining('Skill loaded'), findsOneWidget);

    // Close modal
    await tester.tap(find.byIcon(HarnessIcons.x));
    await tester.pumpAndSettle();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('AppBar action icons navigate to respective routes',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 1. Test Sessions navigation
    await tester.tap(find.byIcon(HarnessIcons.sessions));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.text('FEAT-005'), findsOneWidget);

    // Pop back to ChatScreen
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    // 2. Test Workspace navigation
    await tester.tap(find.byIcon(HarnessIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace & Skills'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.text('FEAT-003 & FEAT-004'), findsOneWidget);

    // Pop back to ChatScreen
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    // 3. Test Settings navigation
    await tester.tap(find.byIcon(HarnessIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Pop back to ChatScreen
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Authentication error dialog directs to Settings',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Emit authentication error
    sessionBloc.emit(const HarnessSessionError(
      errorMessage: 'API key is missing or invalid for claude.',
      isAuthError: true,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Authentication Error'), findsOneWidget);
    expect(find.text('Go to Settings'), findsOneWidget);

    // Tap 'Go to Settings' action
    await tester.tap(find.text('Go to Settings'));
    await tester.pumpAndSettle();

    // Verify navigated to SettingsScreen
    expect(find.byType(SettingsScreen), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Memory limit error dialog directs to Settings',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Emit memory limit error
    sessionBloc.emit(const HarnessSessionError(
      errorMessage: 'On-device SLM exceeded mobile memory limit (1024MB > 512MB).',
      isMemoryError: true,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Memory Limit Exceeded'), findsOneWidget);
    expect(find.text('Switch Model'), findsOneWidget);

    // Tap 'Switch Model' action
    await tester.tap(find.text('Switch Model'));
    await tester.pumpAndSettle();

    // Verify navigated to SettingsScreen
    expect(find.byType(SettingsScreen), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets('Model quick select sheet displays Present/Missing and Key Configured/Key Missing using theme',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Tap title area to open quick select sheet
    final titleFinder = find.text('Harness');
    expect(titleFinder, findsOneWidget);
    await tester.tap(titleFinder);
    await tester.pumpAndSettle();

    // Verify bottom sheet title is visible
    expect(find.text('Select Active Model'), findsOneWidget);

    // Verify status strings for on-device and cloud providers
    // By default, no local model is downloaded, so it should display ' • Missing'
    expect(find.textContaining('Missing'), findsWidgets);

    // Close bottom sheet
    await tester.tap(find.byIcon(HarnessIcons.settings).last);
    await tester.pumpAndSettle();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });

  testWidgets(
      'anchors a live A2UI surface to its first turn and updates it in place',
      (WidgetTester tester) async {
    final switcherBloc = ModelSwitcherBloc(
      database: database,
      keyStorage: keyStorage,
    )..add(const LoadProviderConfigsEvent());

    final sessionBloc = HarnessSessionBloc(
      engine: engine,
      keyStorage: keyStorage,
    );

    await tester.pumpWidget(createTestableChatScreen(
      sessionBloc: sessionBloc,
      switcherBloc: switcherBloc,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final store = A2UISurfaceStore();
    store.applyMessages([
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'board',
          'catalogId': 'basic/v1',
          'components': [
            {'id': 'root', 'component': 'Text', 'text': 'Board v1'},
          ],
        },
      },
    ]);

    Turn a2uiTurn(String id, String text) => Turn(
          id: id,
          sessionId: 'sess_surface',
          timestamp: DateTime.now(),
          sender: 'agent',
          contentType: 'a2ui',
          text: text,
          a2uiSurfaceId: 'board',
        );

    final turns = [
      a2uiTurn('turn_surface_1', 'Opening move'),
      a2uiTurn('turn_surface_2', 'Opponent replied'),
      Turn(
        id: 'turn_user_2',
        sessionId: 'sess_surface',
        timestamp: DateTime.now(),
        sender: 'user',
        contentType: 'text',
        text: 'Cell 0',
      ),
    ];

    sessionBloc.emit(HarnessSessionReady(
      sessionId: 'sess_surface',
      turns: turns,
      surfaces: store.surfaces,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The first A2UI turn owns the only surface. Later A2UI turns add no chat
    // item at all, and recorded A2UI text is never rendered as companion text.
    expect(find.byType(A2UISurfaceView), findsOneWidget);
    expect(find.text('Board v1'), findsOneWidget);
    expect(find.text('Opening move'), findsNothing);
    expect(find.text('Opponent replied'), findsNothing);
    expect(find.text('Cell 0'), findsOneWidget);

    final anchorBubble = tester.widget<MessageBubble>(
      find
          .ancestor(
            of: find.byType(A2UISurfaceView),
            matching: find.byType(MessageBubble),
          )
          .first,
    );
    expect(anchorBubble.turn.id, 'turn_surface_1');

    // The surface stays above the newer user turn instead of moving down.
    expect(
      tester.getTopLeft(find.byType(A2UISurfaceView)).dy,
      lessThan(tester.getTopLeft(find.text('Cell 0')).dy),
    );

    // A later update to the same surfaceId mutates the anchored surface in
    // place instead of adding another copy to the stream.
    store.applyMessages([
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'board',
          'components': [
            {'id': 'root', 'component': 'Text', 'text': 'Board v2'},
          ],
        },
      },
    ]);
    sessionBloc.emit(HarnessSessionReady(
      sessionId: 'sess_surface',
      turns: turns,
      surfaces: store.surfaces,
    ));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(A2UISurfaceView), findsOneWidget);
    expect(find.text('Board v1'), findsNothing);
    expect(find.text('Board v2'), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });
}
