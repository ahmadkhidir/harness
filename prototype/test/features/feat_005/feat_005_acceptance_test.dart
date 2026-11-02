import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/storage/storage_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/providers/model_provider.dart';

class _MockEngineProvider extends ModelProvider {
  String responseText = 'Default response';

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'mock_provider',
        providerType: 'gemini',
        displayName: 'Mock Provider',
        modelName: 'mock-model',
        isActive: true,
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    return responseText;
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
  late _MockEngineProvider mockModel;
  late HarnessEngine engine;
  late StorageModule storage;
  late CommandRouter router;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('feat_005_acceptance_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
    db = AppDatabase.inMemory();
    sessionService = SessionService(
      fileSystem: fs,
      database: db,
      compactionThresholdBytes: 300, // Compact at 300 bytes for deterministic testing
    );

    mockModel = _MockEngineProvider();
    router = CommandRouter();
    storage = StorageModule(fileSystem: fs);
    router.registerModule(storage);

    engine = HarnessEngine(
      router: router,
      contextBuilder: ContextBuilder(),
      modelProvider: mockModel,
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('FEAT-005 Acceptance Tests - Dual-File Isolated Session Management & Compaction', () {
    test('Criterion 1: User message and final agent delivery synchronously dual-write across turns.json and context.txt', () async {
      final session = await sessionService.createSession(title: 'Dual-Write Test');
      mockModel.responseText = '<system_call>{"command": "send_message", "parameters": {"text": "Photosynthesis produces glucose and oxygen."}}</system_call>';

      final bloc = HarnessSessionBloc(
        engine: engine,
        sessionService: sessionService,
      );
      bloc.add(InitializeSessionEvent(sessionId: session.id));
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.add(const SubmitUserPromptEvent('What are the products of photosynthesis?'));

      // Wait for turn completion
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<HarnessSessionState>((state) {
          return state is HarnessSessionReady && state.turns.length == 2;
        })),
      );

      // Verify context.txt on disk
      final contextFile = fs.sessionContextFile(session.id);
      expect(contextFile.existsSync(), isTrue);
      final lines = contextFile.readAsLinesSync();
      expect(lines.length, equals(2));
      expect(lines[0], equals('USER: What are the products of photosynthesis?'));
      expect(lines[1], equals('AGENT: Photosynthesis produces glucose and oxygen.'));

      // Verify turns.json on disk
      final turnsFile = fs.sessionTurnsFile(session.id);
      expect(turnsFile.existsSync(), isTrue);
      final savedTurns = await sessionService.loadTurns(session.id);
      expect(savedTurns.length, equals(2));
      expect(savedTurns[0].sender, equals('user'));
      expect(savedTurns[0].text, equals('What are the products of photosynthesis?'));
      expect(savedTurns[1].sender, equals('agent'));
      expect(savedTurns[1].text, equals('Photosynthesis produces glucose and oxygen.'));

      await bloc.close();
    });

    test('Criterion 2: Agent can execute grep(path: "context.txt", pattern: "...") to search past dialogue', () async {
      final session = await sessionService.createSession(title: 'Grep Context Test');
      await sessionService.appendTurn(
        session.id,
        Turn(
          id: 'turn_past_1',
          sessionId: session.id,
          timestamp: DateTime.now().toUtc(),
          sender: 'user',
          contentType: 'text',
          text: 'The server port is configured to 8088.',
        ),
      );
      await sessionService.appendTurn(
        session.id,
        Turn(
          id: 'turn_past_2',
          sessionId: session.id,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: 'Acknowledged. Server port 8088 is registered in system settings.',
        ),
      );

      // Execute grep directly on context.txt
      storage.activeSessionId = session.id;
      final grepResult = await storage.executeCommand('grep', {
        'path': 'context.txt',
        'pattern': '8088',
      });

      expect(grepResult.isSuccess, isTrue);
      final matches = grepResult.data as List;
      expect(matches.length, equals(2));
      expect(matches[0]['file'], equals('context.txt'));
      expect(matches[0]['line'], equals(1));
      expect(matches[0]['content'], contains('8088'));
      expect(matches[1]['file'], equals('context.txt'));
      expect(matches[1]['line'], equals(2));
    });

    test('Criterion 3 & 4: Compaction rewrites context.txt with SUMMARY: while chat UI preserves full uncompacted history from turns.json', () async {
      final session = await sessionService.createSession(title: 'Compaction Full Test');

      // Populate enough dialogue to exceed the 300-byte threshold
      for (int i = 1; i <= 5; i++) {
        await sessionService.appendTurn(
          session.id,
          Turn(
            id: 'u_$i',
            sessionId: session.id,
            timestamp: DateTime.now().toUtc(),
            sender: 'user',
            contentType: 'text',
            text: 'User query $i regarding atmospheric pressure and temperature gradients at high altitudes.',
          ),
        );
        await sessionService.appendTurn(
          session.id,
          Turn(
            id: 'a_$i',
            sessionId: session.id,
            timestamp: DateTime.now().toUtc(),
            sender: 'agent',
            contentType: 'text',
            text: 'Agent analysis $i: Atmospheric pressure decreases logarithmically with altitude in the troposphere.',
          ),
        );
      }

      final contextFile = fs.sessionContextFile(session.id);
      expect(contextFile.lengthSync() > 300, isTrue);

      // Trigger compaction
      final didCompact = await sessionService.checkAndCompact(session.id);
      expect(didCompact, isTrue);

      // Verify context.txt structure: Line 1 must begin with SUMMARY:
      final contextLines = contextFile.readAsLinesSync();
      expect(contextLines.first.startsWith('SUMMARY: '), isTrue);

      // Criterion 4: Verify turns.json STILL HAS ALL 10 UNCOMPACTED TURNS
      final loadedTurns = await sessionService.loadTurns(session.id);
      expect(loadedTurns.length, equals(10));
      for (int i = 1; i <= 5; i++) {
        expect(loadedTurns.any((t) => t.id == 'u_$i'), isTrue);
        expect(loadedTurns.any((t) => t.id == 'a_$i'), isTrue);
      }

      // Verify Session entity compaction metadata
      final updatedSession = await sessionService.getSession(session.id);
      expect(updatedSession?.compactionCount, equals(1));
      expect(updatedSession?.lastCompactedAt, isNotNull);
    });

    test('Criterion 5: Sibling session directory access is strictly prohibited', () async {
      final sessionA = await sessionService.createSession(title: 'Session Alpha');
      final sessionB = await sessionService.createSession(title: 'Session Beta');

      storage.activeSessionId = sessionA.id;

      // Accessing sibling context file
      final readAttempt = await storage.executeCommand('read_file', {
        'path': 'sessions/${sessionB.id}/context.txt',
      });
      expect(readAttempt.isError, isTrue);
      expect(readAttempt.errorMessage, contains('Sibling session access is prohibited'));

      // Accessing sibling directory via glob
      final globAttempt = await storage.executeCommand('glob', {
        'path': 'sessions/${sessionB.id}',
        'pattern': '*',
      });
      expect(globAttempt.isError, isTrue);
      expect(globAttempt.errorMessage, contains('Sibling session access is prohibited'));

      // Accessing sessions parent folder
      final listAttempt = await storage.executeCommand('list_directory', {
        'path': 'sessions',
      });
      expect(listAttempt.isError, isTrue);
      expect(listAttempt.errorMessage, contains('Sibling session access is prohibited'));
    });

    test('Edge Case 1: Atomic compaction via .tmp file prevents file corruption', () async {
      final session = await sessionService.createSession(title: 'Atomic Compaction Test');

      for (int i = 1; i <= 4; i++) {
        await sessionService.appendTurn(
          session.id,
          Turn(
            id: 't_$i',
            sessionId: session.id,
            timestamp: DateTime.now().toUtc(),
            sender: 'user',
            contentType: 'text',
            text: 'Payload data segment $i with sufficient byte length for compaction trigger.',
          ),
        );
      }

      final contextFile = fs.sessionContextFile(session.id);
      final initialLength = contextFile.lengthSync();

      await sessionService.compactSession(session.id, keepRecentLines: 1);

      // Verify .tmp file does not linger
      final tmpFile = File('${contextFile.path}.tmp');
      expect(tmpFile.existsSync(), isFalse);
      expect(contextFile.existsSync(), isTrue);
      expect(contextFile.lengthSync() < initialLength || contextFile.readAsLinesSync().first.startsWith('SUMMARY: '), isTrue);
    });

    test('Edge Case 2: Empty session initialization creates valid turns.json with metadata and empty context.txt', () async {
      final session = await sessionService.createSession(title: 'Clean Initialized Thread');

      final turnsFile = fs.sessionTurnsFile(session.id);
      final contextFile = fs.sessionContextFile(session.id);

      expect(turnsFile.existsSync(), isTrue);
      expect(contextFile.existsSync(), isTrue);
      expect(contextFile.lengthSync(), equals(0));

      final metadata = await sessionService.getSession(session.id);
      expect(metadata, isNotNull);
      expect(metadata?.totalTurns, equals(0));
      expect(metadata?.contextSizeBytes, equals(0));
      expect(metadata?.compactionCount, equals(0));
      expect(metadata?.lastCompactedAt, isNull);
    });
  });
}
