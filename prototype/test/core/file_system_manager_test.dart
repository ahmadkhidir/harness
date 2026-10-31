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
      expect(await fileSystem.dataDir.exists(), isTrue);
      expect(await fileSystem.modelsDir.exists(), isTrue);
      expect(await fileSystem.storageDir.exists(), isTrue);
      expect(await fileSystem.skillsDir.exists(), isTrue);
      expect(await fileSystem.sessionsDir.exists(), isTrue);

      // Verify models directory lives under data/
      expect(fileSystem.modelsDir.path.contains('data'), isTrue);
    });

    test('resolves model files cleanly inside data/models/', () {
      final model = fileSystem.modelFile('Qwen3-0.6B.litertlm');
      expect(model.path.contains('data'), isTrue);
      expect(model.path.contains('models'), isTrue);
      expect(model.path.endsWith('Qwen3-0.6B.litertlm'), isTrue);
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

  group('HarnessFileSystem - Virtual Mount Table & Zero Host Path Leakage', () {
    test('resolves primary mount and untagged paths to storage directory', () {
      final file1 = fileSystem.resolveVirtualFile('primary/notes.txt');
      expect(file1.path.endsWith(Platform.isWindows ? r'storage\notes.txt' : 'storage/notes.txt'), isTrue);

      final file2 = fileSystem.resolveVirtualFile('notes.txt');
      expect(file2.path.endsWith(Platform.isWindows ? r'storage\notes.txt' : 'storage/notes.txt'), isTrue);
    });

    test('supports registering external mounts and resolves tagged paths', () async {
      final externalTemp = await Directory.systemTemp.createTemp('external_mount_');
      try {
        fileSystem.mounts.registerMount('downloads', externalTemp);

        expect(fileSystem.mounts.mountTags, contains('downloads'));
        final extFile = fileSystem.resolveVirtualFile('downloads/dataset.csv');
        expect(extFile.path.contains('external_mount_'), isTrue);
        expect(extFile.path.endsWith('dataset.csv'), isTrue);

        // Path traversal out of external mount is blocked
        expect(
          () => fileSystem.resolveVirtualFile('downloads/../../secret.txt'),
          throwsA(isA<SecurityException>()),
        );
      } finally {
        await externalTemp.delete(recursive: true);
      }
    });

    test('formatFilesystemTree conceals real host paths and exposes virtual tags', () async {
      final externalTemp = await Directory.systemTemp.createTemp('external_downloads_');
      try {
        final dummyFile = File('${externalTemp.path}/sample.txt');
        await dummyFile.writeAsString('hello');

        fileSystem.mounts.registerMount('downloads', externalTemp);
        final tree = fileSystem.formatFilesystemTree();

        expect(tree.startsWith('<filesystem>'), isTrue);
        expect(tree.endsWith('</filesystem>'), isTrue);
        expect(tree.contains('primary/'), isTrue);
        expect(tree.contains('downloads/'), isTrue);
        expect(tree.contains('sample.txt'), isTrue);

        // Strict Zero Host Path Leakage: host temporary path must NEVER appear in tree
        expect(tree.contains(externalTemp.path), isFalse);
        expect(tree.contains(fileSystem.rootDir.path), isFalse);
      } finally {
        await externalTemp.delete(recursive: true);
      }
    });

    test('disallows unregistering primary mount', () {
      expect(
        () => fileSystem.mounts.unregisterMount('primary'),
        throwsArgumentError,
      );
    });
  });
}
