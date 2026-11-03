import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/modules/a2ui/widgets/a2ui_media_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_a2ui_media_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
  });

  tearDown(() async {
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('A2UIMediaSource - FEAT-009', () {
    test('keeps remote http(s) sources as network URLs', () {
      final source = A2UIMediaSource.resolve('https://example.com/a.png');

      expect(source.isLocal, isFalse);
      expect(source.networkUrl, 'https://example.com/a.png');
      expect(source.isEmpty, isFalse);
    });

    test('resolves virtual storage paths to local files', () async {
      final file = File(p.join(fileSystem.storageDir.path, 'cover.png'));
      await file.writeAsString('bytes');

      final source = A2UIMediaSource.resolve('primary/cover.png');

      expect(source.isLocal, isTrue);
      expect(source.file?.path, p.canonicalize(file.path));
    });

    test('resolves bare relative paths inside primary', () async {
      final file = File(p.join(fileSystem.storageDir.path, 'cover.png'));
      await file.writeAsString('bytes');

      final source = A2UIMediaSource.resolve('cover.png');

      expect(source.file?.path, p.canonicalize(file.path));
    });

    test('accepts the harness-file prefix', () async {
      final file = File(p.join(fileSystem.storageDir.path, 'cover.png'));
      await file.writeAsString('bytes');

      final source = A2UIMediaSource.resolve('harness-file:primary/cover.png');

      expect(source.file?.path, p.canonicalize(file.path));
    });

    test('rejects traversal and unknown volumes', () {
      expect(A2UIMediaSource.resolve('../secret.png').isEmpty, isTrue);
      expect(A2UIMediaSource.resolve('missing/secret.png').isEmpty, isTrue);
    });
  });
}
