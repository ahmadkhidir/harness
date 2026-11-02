import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/context_line.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fs;
  late AppDatabase db;
  late SessionService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_service_test_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
    db = AppDatabase.inMemory();
    service = SessionService(
      fileSystem: fs,
      database: db,
      compactionThresholdBytes: 250, // Small threshold for testing compaction
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('createSession synthesizes empty turns.json with metadata and empty context.txt', () async {
    final session = await service.createSession(title: 'Research Project');

    expect(session.id, startsWith('sess_'));
    expect(session.title, equals('Research Project'));
    expect(session.totalTurns, equals(0));
    expect(session.contextSizeBytes, equals(0));
    expect(session.compactionCount, equals(0));
    expect(session.lastCompactedAt, isNull);

    final turnsFile = fs.sessionTurnsFile(session.id);
    final contextFile = fs.sessionContextFile(session.id);

    expect(turnsFile.existsSync(), isTrue);
    expect(contextFile.existsSync(), isTrue);
    expect(contextFile.lengthSync(), equals(0));

    final turns = await service.loadTurns(session.id);
    expect(turns, isEmpty);

    final activeId = await service.getActiveSessionId();
    expect(activeId, equals(session.id));
  });

  test('appendTurn performs synchronous dual-write across turns.json and context.txt', () async {
    final session = await service.createSession(title: 'Chat Session');

    final userTurn = Turn(
      id: 'turn_001',
      sessionId: session.id,
      timestamp: DateTime.now().toUtc(),
      sender: 'user',
      contentType: 'text',
      text: 'What is the speed of light?',
    );

    await service.appendTurn(session.id, userTurn);

    // Verify context.txt line format
    final contextFile = fs.sessionContextFile(session.id);
    final contextLines = contextFile.readAsLinesSync();
    expect(contextLines.length, equals(1));
    expect(contextLines[0], equals('USER: What is the speed of light?'));

    // Verify turns.json content and updated session metadata
    final loadedTurns = await service.loadTurns(session.id);
    expect(loadedTurns.length, equals(1));
    expect(loadedTurns[0].id, equals('turn_001'));
    expect(loadedTurns[0].text, equals('What is the speed of light?'));

    final updatedSession = await service.getSession(session.id);
    expect(updatedSession?.totalTurns, equals(1));
    expect(updatedSession?.contextSizeBytes, equals(contextFile.lengthSync()));

    // Append agent turn
    final agentTurn = Turn(
      id: 'turn_002',
      sessionId: session.id,
      timestamp: DateTime.now().toUtc(),
      sender: 'agent',
      contentType: 'text',
      text: 'The speed of light is approximately 299,792 km/s.',
    );

    await service.appendTurn(session.id, agentTurn);

    final updatedContextLines = contextFile.readAsLinesSync();
    expect(updatedContextLines.length, equals(2));
    expect(
      updatedContextLines[1],
      equals('AGENT: The speed of light is approximately 299,792 km/s.'),
    );

    final turnsAfterAgent = await service.loadTurns(session.id);
    expect(turnsAfterAgent.length, equals(2));
  });

  test('compactSession produces atomic SUMMARY line at line 1 and retains all turns in turns.json', () async {
    final session = await service.createSession(title: 'Compaction Test');

    // Add several conversational turns to exceed the 250 bytes threshold
    for (int i = 1; i <= 6; i++) {
      await service.appendTurn(
        session.id,
        Turn(
          id: 'turn_u$i',
          sessionId: session.id,
          timestamp: DateTime.now().toUtc(),
          sender: 'user',
          contentType: 'text',
          text: 'Topic $i: Can you explain detail $i about quantum mechanics and astrophysics in depth?',
        ),
      );
      await service.appendTurn(
        session.id,
        Turn(
          id: 'turn_a$i',
          sessionId: session.id,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: 'Response $i: Here are the detailed scientific insights and explanations for step $i.',
        ),
      );
    }

    final contextFile = fs.sessionContextFile(session.id);
    expect(contextFile.lengthSync() > 250, isTrue);

    // Trigger compaction keeping the 2 most recent dialogue lines
    final compacted = await service.compactSession(session.id, keepRecentLines: 2);
    expect(compacted, isTrue);

    // Verify context.txt structure: Line 1 MUST be SUMMARY:
    final lines = contextFile.readAsLinesSync();
    expect(lines.first.startsWith('SUMMARY: '), isTrue);
    expect(lines.length, equals(3)); // 1 summary line + 2 recent dialogue lines

    final parsedSummary = ContextLine.parse(lines[0]);
    expect(parsedSummary.type, equals(ContextLineType.summary));
    expect(parsedSummary.content.contains('Topic 1'), isTrue);

    // Verify turns.json STILL HAS ALL 12 TURNS UNTOUCHED
    final allTurns = await service.loadTurns(session.id);
    expect(allTurns.length, equals(12));

    // Verify session metadata is updated with compaction count
    final metadata = await service.getSession(session.id);
    expect(metadata?.compactionCount, equals(1));
    expect(metadata?.lastCompactedAt, isNotNull);
    expect(metadata?.contextSizeBytes, equals(contextFile.lengthSync()));
  });

  test('renameSession and deleteSession maintain state consistency', () async {
    final s1 = await service.createSession(title: 'Session Alpha');
    final s2 = await service.createSession(title: 'Session Beta');

    expect(await service.getActiveSessionId(), equals(s2.id));

    final renamed = await service.renameSession(s1.id, 'Session Alpha Prime');
    expect(renamed.title, equals('Session Alpha Prime'));

    final fetched = await service.getSession(s1.id);
    expect(fetched?.title, equals('Session Alpha Prime'));

    // Delete active session s2
    await service.deleteSession(s2.id);
    expect(fs.sessionDir(s2.id).existsSync(), isFalse);

    // Active session should automatically fall back to remaining s1
    final newActive = await service.getActiveSessionId();
    expect(newActive, equals(s1.id));

    final all = await service.getAllSessions();
    expect(all.length, equals(1));
    expect(all.first.id, equals(s1.id));
  });
}
