import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/modules/storage/storage_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fs;
  late AppDatabase db;
  late SessionService sessionService;
  late StorageModule storage;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('storage_session_iso_test_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
    db = AppDatabase.inMemory();
    sessionService = SessionService(fileSystem: fs, database: db);

    storage = StorageModule(fileSystem: fs);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('grep cannot reach the internal session context.txt', () async {
    final session = await sessionService.createSession(title: 'History Query Test');
    await sessionService.appendTurn(
      session.id,
      Turn(
        id: 'turn_1',
        sessionId: session.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'text',
        text: 'My secret recipe includes saffron and wild blueberries.',
      ),
    );
    await sessionService.appendTurn(
      session.id,
      Turn(
        id: 'turn_2',
        sessionId: session.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'text',
        text: 'I have noted that your secret recipe includes saffron and wild blueberries.',
      ),
    );

    // Set active session in storage module
    storage.activeSessionId = session.id;

    final grepResponse = await storage.executeCommand('grep', {
      'path': 'context.txt',
      'pattern': 'saffron',
    });

    expect(grepResponse.isError, isTrue);
  });

  test('read_file cannot reach the internal session context.txt', () async {
    final session = await sessionService.createSession(title: 'Read Context Test');
    await sessionService.appendTurn(
      session.id,
      Turn(
        id: 't1',
        sessionId: session.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'text',
        text: 'Line 1 text',
      ),
    );
    await sessionService.appendTurn(
      session.id,
      Turn(
        id: 't2',
        sessionId: session.id,
        timestamp: DateTime.now().toUtc(),
        sender: 'agent',
        contentType: 'text',
        text: 'Line 2 text',
      ),
    );

    storage.activeSessionId = session.id;

    final readResponse = await storage.executeCommand('read_file', {
      'path': 'context.txt',
      'start_line': 2,
      'end_line': 2,
    });

    expect(readResponse.isError, isTrue);
  });

  test('Strict session isolation: Sibling session directory access is blocked', () async {
    final activeSession = await sessionService.createSession(title: 'Active Session');
    final siblingSession = await sessionService.createSession(title: 'Sibling Session');

    storage.activeSessionId = activeSession.id;

    // 1. Attempting to read sibling context.txt
    final readSibling = await storage.executeCommand('read_file', {
      'path': 'sessions/${siblingSession.id}/context.txt',
    });
    expect(readSibling.isError, isTrue);
    expect(readSibling.errorMessage, contains('Sibling session access is prohibited'));

    // 2. Attempting to write into sibling session folder
    final writeSibling = await storage.executeCommand('write_file', {
      'path': 'sessions/${siblingSession.id}/hack.txt',
      'content': 'Exploit attempt',
    });
    expect(writeSibling.isError, isTrue);
    expect(writeSibling.errorMessage, contains('Sibling session access is prohibited'));

    // 3. Attempting to grep sibling session folder
    final grepSibling = await storage.executeCommand('grep', {
      'path': 'sessions/${siblingSession.id}',
      'pattern': '.*',
    });
    expect(grepSibling.isError, isTrue);
    expect(grepSibling.errorMessage, contains('Sibling session access is prohibited'));

    // 4. Attempting to list all sessions directory
    final listSessions = await storage.executeCommand('list_directory', {
      'path': 'sessions',
    });
    expect(listSessions.isError, isTrue);
    expect(listSessions.errorMessage, contains('Sibling session access is prohibited'));
  });
}
