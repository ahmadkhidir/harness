import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/context_line.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;
  late SessionService sessionService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_transcript_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
    sessionService = SessionService(
      fileSystem: fileSystem,
      database: AppDatabase.inMemory(),
    );
  });

  tearDown(() async {
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Turn userTurn(String id, String text) => Turn(
        id: id,
        sessionId: 'unused',
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'text',
        text: text,
      );

  group('Session context transcript', () {
    test('UI turns do not write to context until the user line is appended',
        () async {
      final session = await sessionService.createSession(title: 'Transcript');
      await sessionService.appendUiTurn(
        session.id,
        userTurn('u1', 'Hello'),
      );

      final contextFile = fileSystem.sessionContextFile(session.id);
      expect(contextFile.readAsStringSync().trim(), isEmpty);
      expect((await sessionService.loadTurns(session.id)).length, 1);

      await sessionService.appendUserContextLine(session.id, 'Hello');
      expect(contextFile.readAsStringSync(), contains('USER: Hello'));
    });

    test('tool observations persist success, error, and truncation', () async {
      final session = await sessionService.createSession(title: 'Tools');
      await sessionService.appendUserContextLine(session.id, 'Read this');

      await sessionService.appendToolObservation(
        session.id,
        command: 'read_file',
        parameters: {'path': 'primary/missing.txt'},
        success: false,
        error: 'File not found: primary/missing.txt',
      );
      await sessionService.appendToolObservation(
        session.id,
        command: 'web_search',
        parameters: {'query': 'x' * 1500},
        success: true,
        output: 'result ' * 1000,
      );

      final lines = fileSystem
          .sessionContextFile(session.id)
          .readAsStringSync()
          .trim()
          .split('\n');
      final toolLines =
          lines.where((line) => line.startsWith('TOOL: ')).toList();
      expect(toolLines, hasLength(2));

      final errorLine = ContextLine.parse(toolLines[0]);
      expect(errorLine.type, ContextLineType.tool);
      expect(errorLine.content, contains('"status":"error"'));
      expect(errorLine.content, contains('File not found'));

      final successLine = ContextLine.parse(toolLines[1]);
      expect(successLine.content, contains('"status":"success"'));
      expect(successLine.content, contains('"truncated":true'));
      expect(successLine.content.length, lessThan(6000));
    });

    test('transcript excludes a trailing current prompt when requested',
        () async {
      final session = await sessionService.createSession(title: 'Strip');
      await sessionService.appendUserContextLine(session.id, 'First');
      await sessionService.appendUserContextLine(session.id, 'Second');

      final transcript = await sessionService.readContextTranscript(
        session.id,
        excludePrompt: 'Second',
      );

      expect(transcript, contains('USER: First'));
      expect(transcript, isNot(contains('USER: Second')));
    });

    test('compaction summarizes tool lines and keeps the recent tail',
        () async {
      final session = await sessionService.createSession(title: 'Compact');
      await sessionService.appendUserContextLine(session.id, 'First');
      await sessionService.appendToolObservation(
        session.id,
        command: 'read_file',
        parameters: {'path': 'primary/a.txt'},
        success: false,
        error: 'Access denied',
      );
      await sessionService.appendUserContextLine(session.id, 'Second');
      await sessionService.appendUserContextLine(session.id, 'Third');

      final compacted = await sessionService.compactSession(
        session.id,
        keepRecentLines: 1,
      );

      expect(compacted, isTrue);
      final lines = fileSystem
          .sessionContextFile(session.id)
          .readAsStringSync()
          .trim()
          .split('\n');
      expect(lines.first, startsWith('SUMMARY: '));
      expect(lines.first, contains('Tool read_file error'));
      expect(lines.first, contains('Access denied'));
      expect(lines.length, lessThanOrEqualTo(21));
      expect(lines.last, contains('Third'));
    });
  });
}
