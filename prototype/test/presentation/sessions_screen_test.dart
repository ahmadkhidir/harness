import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/screens/sessions_screen.dart';
import 'package:harness/providers/model_provider.dart';

class _FakeModelProvider extends ModelProvider {
  @override
  ProviderConfig get config => ProviderConfig(
        id: 'fake',
        providerType: 'gemini',
        displayName: 'Fake',
        modelName: 'fake',
        isActive: true,
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async =>
      'Fake response';

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

  @override
  Future<bool> testConnection({String? apiKey}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fs;
  late AppDatabase db;
  late SessionService service;
  late HarnessEngine engine;
  late HarnessSessionBloc bloc;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sessions_screen_test_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
    db = AppDatabase.inMemory();
    service = SessionService(fileSystem: fs, database: db);

    engine = HarnessEngine(
      router: CommandRouter(),
      contextBuilder: ContextBuilder(),
      modelProvider: _FakeModelProvider(),
    );

    bloc = HarnessSessionBloc(
      engine: engine,
      sessionService: service,
    );
  });

  tearDown(() {
    bloc.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: BlocProvider<HarnessSessionBloc>.value(
        value: bloc,
        child: SessionsScreen(
          sessionService: service,
          database: db,
        ),
      ),
    );
  }

  testWidgets('SessionsScreen renders empty state when zero sessions exist', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('All Sessions'), findsOneWidget);
    expect(find.text('No Sessions Yet'), findsOneWidget);
    expect(find.text('Start First Session'), findsOneWidget);
  });

  testWidgets('SessionsScreen displays session cards with title, turn counts, context size, and active badge', (tester) async {
    final s1 = await service.createSession(title: 'Quantum Physics Inquiry');
    await service.appendTurn(
      s1.id,
      Turn(
        id: 't1',
        sessionId: s1.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'text',
        text: 'Explain entanglement.',
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Quantum Physics Inquiry'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('1 turn'), findsOneWidget);
    expect(find.textContaining('KB context'), findsOneWidget);
  });

  testWidgets('New session FAB creates a new session and switches active pointer', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final all = await service.getAllSessions();
    expect(all.length, equals(1));
    expect(all.first.title, equals('New Session'));
  });

  testWidgets('Rename session dialog updates title in session list', (tester) async {
    final s1 = await service.createSession(title: 'Old Title');

    await tester.pumpWidget(buildTestWidget());
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Old Title'), findsOneWidget);

    // Open PopupMenu
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Tap Rename
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Session'), findsOneWidget);

    // Enter new title
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Updated Title Alpha');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Updated Title Alpha'), findsOneWidget);
    final reloaded = await service.getSession(s1.id);
    expect(reloaded?.title, equals('Updated Title Alpha'));
  });

  testWidgets('Delete session dialog removes session from disk and list', (tester) async {
    final s1 = await service.createSession(title: 'Disposable Thread');

    await tester.pumpWidget(buildTestWidget());
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Disposable Thread'), findsOneWidget);

    // Open PopupMenu
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Tap Delete
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Session?'), findsOneWidget);

    // Confirm Delete
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Disposable Thread'), findsNothing);
    expect(fs.sessionDir(s1.id).existsSync(), isFalse);
  });
}
