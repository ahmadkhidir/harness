import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/services/skills_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fs;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('harness_builtin_skill_');
    fs = HarnessFileSystem(rootDir: Directory('${tempDir.path}/Harness'));
    fs.ensureBaseDirectoriesSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('seeds the locked a2ui-basic skill and component references', () async {
    final service = SkillsService(fileSystem: fs);
    await service.seedBuiltinSkills();

    final skillFile = File(
      '${fs.skillsDir.path}/a2ui-basic/SKILL.md',
    );
    final cardFile = File(
      '${fs.skillsDir.path}/a2ui-basic/references/components/card.md',
    );

    expect(skillFile.existsSync(), isTrue);
    expect(cardFile.existsSync(), isTrue);

    final metadata = SkillsService.parseFrontmatter(
      skillFile.readAsStringSync(),
      'a2ui-basic',
    );
    expect(metadata, isNotNull);
    expect(metadata!.isLocked, isTrue);
    expect(metadata.description, contains('interactive UI'));
  });

  test('seeds only on first run; restore brings a deleted skill back', () async {
    final service = SkillsService(fileSystem: fs);
    await service.seedBuiltinSkills();

    final skillDir = Directory('${fs.skillsDir.path}/a2ui-basic');
    skillDir.deleteSync(recursive: true);

    await service.seedBuiltinSkills();
    expect(skillDir.existsSync(), isFalse);

    await service.restoreBuiltinSkill('a2ui-basic');
    expect(skillDir.existsSync(), isTrue);
  });

  test('restore overwrites local edits to a built-in skill', () async {
    final service = SkillsService(fileSystem: fs);
    await service.seedBuiltinSkills();

    final skillFile = File('${fs.skillsDir.path}/a2ui-basic/SKILL.md');
    skillFile.writeAsStringSync('local edit');

    await service.restoreBuiltinSkill('a2ui-basic');

    expect(skillFile.readAsStringSync(), contains('A2UI Basic'));
  });

  test('import refuses to overwrite a locked built-in skill', () async {
    final service = SkillsService(fileSystem: fs);
    await service.seedBuiltinSkills();

    final source = Directory('${tempDir.path}/source')
      ..createSync(recursive: true);
    File('${source.path}/SKILL.md').writeAsStringSync('''
---
name: a2ui-basic
description: Replacement
---
''');

    expect(service.isSkillLocked('a2ui-basic'), isTrue);
    expect(
      () => service.importSkillPackage(
        source: source,
        name: 'a2ui-basic',
        overwrite: true,
      ),
      throwsA(isA<SkillLockedException>()),
    );
  });
}
