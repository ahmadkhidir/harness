import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_test_');
    fileSystem = await HarnessFileSystem.init(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HarnessFileSystem - Layout & Initialization', () {
    test('creates required directory hierarchy', () async {
      expect(await fileSystem.rootDir.exists(), isTrue);
      expect(await fileSystem.databaseDir.exists(), isTrue);
      expect(await fileSystem.skillsDir.exists(), isTrue);
      expect(await fileSystem.storageDir.exists(), isTrue);
      expect(await fileSystem.workspaceDir.exists(), isTrue);
      expect(await fileSystem.downloadsDir.exists(), isTrue);
      expect(await fileSystem.sessionsDir.exists(), isTrue);
    });

    test('resolves session directories cleanly', () {
      final sDir = fileSystem.sessionDir('sess_100');
      expect(sDir.path.endsWith('sess_100'), isTrue);

      final turns = fileSystem.sessionTurnsFile('sess_100');
      expect(turns.path.endsWith('turns.json'), isTrue);

      final context = fileSystem.sessionContextFile('sess_100');
      expect(context.path.endsWith('context.txt'), isTrue);
    });
  });

  group('HarnessFileSystem - Security Sandbox Jail', () {
    test('resolves authorized files inside storage sandbox', () {
      final file = fileSystem.resolveStorageFile('workspace/notes.txt');
      expect(file.path.contains('storage'), isTrue);
    });

    test('rejects path traversal attempting to escape storage sandbox', () {
      expect(
        () => fileSystem.resolveStorageFile('../../database/harness_app.db'),
        throwsA(isA<SecurityException>()),
      );

      expect(
        () => fileSystem.resolveStorageFile('../sessions/sess_1/turns.json'),
        throwsA(isA<SecurityException>()),
      );
    });

    test('rejects path traversal escaping skill directory', () {
      expect(
        () => fileSystem.resolveSkillFile('summarizer', '../../storage/secret.txt'),
        throwsA(isA<SecurityException>()),
      );
    });

    test('rejects path traversal in session and skill names', () {
      expect(
        () => fileSystem.sessionDir('../malicious'),
        throwsA(isA<SecurityException>()),
      );

      expect(
        () => fileSystem.skillDir('..\\malicious'),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}
