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
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/presentation/bloc/model_switcher_bloc.dart';
import 'package:harness/presentation/bloc/model_switcher_event.dart';
import 'package:harness/presentation/screens/chat_screen.dart';
import 'package:harness/presentation/screens/placeholder_screen.dart';
import 'package:harness/presentation/screens/settings_screen.dart';
import 'package:harness/presentation/widgets/empty_state.dart';
import 'package:harness/presentation/widgets/message_bubble.dart';
import 'package:harness/presentation/widgets/system_call_pill.dart';
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
    return '<system_call>\n{"command": "send_message", "parameters": {"text": "I completed the task."}}\n</system_call>';
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
              title: 'Workspace & Skills',
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
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Verify empty state is displayed when there are no turns
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Welcome to Harness'), findsOneWidget);
    expect(find.text('What commands can you execute?'), findsOneWidget);

    // Verify bottom prompt input bar
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

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
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
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

  testWidgets('Displays live execution status and SystemCallPill tray during run',
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
      command: 'web_search',
      parameters: const {'query': 'Flutter'},
    );

    sessionBloc.emit(HarnessTurnExecuting(
      sessionId: 'sess_test_1',
      turns: const [],
      statusMessage: 'Searching the web...',
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

    // Verify live progress spinner, status message, and pill badge
    expect(find.text('Searching the web...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byType(SystemCallPill), findsOneWidget);
    expect(find.text('web_search'), findsOneWidget);

    // Verify send button toggled to stop execution button
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

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
    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.text('FEAT-005'), findsOneWidget);

    // Pop back to ChatScreen
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    // 2. Test Workspace navigation
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.text('FEAT-003 & FEAT-004'), findsOneWidget);

    // Pop back to ChatScreen
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    // 3. Test Settings navigation
    await tester.tap(find.byIcon(Icons.settings_outlined));
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
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    sessionBloc.close();
    switcherBloc.close();
  });
}
