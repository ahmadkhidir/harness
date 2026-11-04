import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/services/skills_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;
  late SkillsService skillsService;
  late Directory source;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_skill_import_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
    skillsService = SkillsService(fileSystem: fileSystem);

    source = Directory(p.join(tempDir.path, 'incoming', 'my-skill'));
    await Directory(p.join(source.path, 'references')).create(recursive: true);
    await File(p.join(source.path, 'SKILL.md')).writeAsString('''
---
name: my-skill
description: A test skill for importing
version: 1.2.3
---
# Workflow
- Do the thing
''');
    await File(p.join(source.path, 'references', 'notes.md'))
        .writeAsString('reference');
  });

  tearDown(() async {
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('SkillsService import', () {
    test('validates a skill package and copies it into skills/', () async {
      final validation = skillsService.validateSkillDirectory(source);
      expect(validation.isValid, isTrue);
      expect(validation.metadata?.name, 'my-skill');
      expect(validation.metadata?.version, '1.2.3');

      await skillsService.importSkillPackage(
        source: source,
        name: validation.metadata!.name,
      );

      final destination = Directory(
        p.join(fileSystem.skillsDir.path, 'my-skill'),
      );
      expect(await File(p.join(destination.path, 'SKILL.md')).exists(), isTrue);
      expect(
        await File(p.join(destination.path, 'references', 'notes.md')).exists(),
        isTrue,
      );
      expect(
        skillsService.scanAvailableSkills().map((skill) => skill.name),
        contains('my-skill'),
      );
    });

    test('rejects folders without SKILL.md', () async {
      final empty = Directory(p.join(tempDir.path, 'incoming', 'empty'));
      await empty.create(recursive: true);

      final validation = skillsService.validateSkillDirectory(empty);

      expect(validation.isValid, isFalse);
      expect(validation.error, contains('SKILL.md'));
    });

    test('rejects a source inside the skills directory', () async {
      final nested = Directory(p.join(fileSystem.skillsDir.path, 'nested'));
      await nested.create(recursive: true);
      await File(p.join(nested.path, 'SKILL.md')).writeAsString('# Nested');

      final validation = skillsService.validateSkillDirectory(nested);

      expect(validation.isValid, isFalse);
      expect(validation.error, contains('already inside'));
    });

    test('refuses to overwrite an existing skill by default', () async {
      await skillsService.importSkillPackage(source: source, name: 'my-skill');

      expect(
        () => skillsService.importSkillPackage(
          source: source,
          name: 'my-skill',
        ),
        throwsA(isA<SkillAlreadyExistsException>()),
      );
    });

    test('overwrites an existing skill when requested', () async {
      final destination = Directory(
        p.join(fileSystem.skillsDir.path, 'my-skill'),
      );
      await destination.create(recursive: true);
      await File(p.join(destination.path, 'old.md')).writeAsString('old');

      await skillsService.importSkillPackage(
        source: source,
        name: 'my-skill',
        overwrite: true,
      );

      expect(await File(p.join(destination.path, 'old.md')).exists(), isFalse);
      expect(await File(p.join(destination.path, 'SKILL.md')).exists(), isTrue);
    });
  });
}
