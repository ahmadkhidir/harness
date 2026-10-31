import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/skills_service.dart';
import 'package:harness/modules/skills/skills_module.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late HarnessFileSystem fs;
  late SkillsService skillsService;
  late SkillsModule skillsModule;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('harness_skills_module_test_');
    db = AppDatabase.inMemory();
    fs = await HarnessFileSystem.init(tempDir, db);
    skillsService = SkillsService(fileSystem: fs);
    skillsModule = SkillsModule(skillsService: skillsService);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SkillsModule specifications', () {
    test('moduleName is "skills"', () {
      expect(skillsModule.moduleName, equals('skills'));
    });

    test('exposes load_skill and load_skill_file commands with schemas', () {
      final commands = skillsModule.commands;
      expect(commands.length, equals(2));

      final loadSkill = commands.firstWhere((c) => c.command == 'load_skill');
      expect(loadSkill.description, isNotEmpty);
      expect(loadSkill.parametersSchema['properties'], contains('name'));
      expect(loadSkill.parametersSchema['required'], contains('name'));

      final loadSkillFile = commands.firstWhere((c) => c.command == 'load_skill_file');
      expect(loadSkillFile.description, isNotEmpty);
      expect(loadSkillFile.parametersSchema['properties'], contains('name'));
      expect(loadSkillFile.parametersSchema['properties'], contains('path'));
      expect(loadSkillFile.parametersSchema['required'], contains('name'));
      expect(loadSkillFile.parametersSchema['required'], contains('path'));
    });
  });

  group('SkillsModule load_skill execution', () {
    test('returns success with SKILL.md content when skill exists', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'summarizer'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(
        '# Summarizer Instructions\nExtract key points.',
      );

      final response = await skillsModule.executeCommand(
        'load_skill',
        {'name': 'summarizer'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.command, equals('load_skill'));
      expect(response.data, equals('# Summarizer Instructions\nExtract key points.'));
      expect(response.toXmlString(), contains('# Summarizer Instructions'));
    });

    test('returns error observation when skill does not exist', () async {
      final response = await skillsModule.executeCommand(
        'load_skill',
        {'name': 'nonexistent-skill'},
      );

      expect(response.isError, isTrue);
      expect(response.command, equals('load_skill'));
      expect(response.errorMessage, equals('Skill or file not found'));
      expect(response.toXmlString(), contains('Skill or file not found'));
    });

    test('returns error when "name" parameter is omitted or empty', () async {
      final response = await skillsModule.executeCommand(
        'load_skill',
        {'name': ''},
      );

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Missing required parameter'));
    });
  });

  group('SkillsModule load_skill_file execution', () {
    test('returns success with auxiliary file content when file exists', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'analyzer'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# Analyzer');

      final refDir = Directory(p.join(skillDir.path, 'references'));
      await refDir.create(recursive: true);
      await File(p.join(refDir.path, 'spec.md')).writeAsString('Detailed Spec Content');

      final response = await skillsModule.executeCommand(
        'load_skill_file',
        {'name': 'analyzer', 'path': 'references/spec.md'},
      );

      expect(response.isSuccess, isTrue);
      expect(response.command, equals('load_skill_file'));
      expect(response.data, equals('Detailed Spec Content'));
    });

    test('returns security error observation when path traversal is attempted', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'secure-skill'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# Secure Skill');

      final response = await skillsModule.executeCommand(
        'load_skill_file',
        {'name': 'secure-skill', 'path': '../../database/app.db'},
      );

      expect(response.isError, isTrue);
      expect(response.command, equals('load_skill_file'));
      expect(response.errorMessage, contains('Access denied'));
      expect(response.errorMessage, contains('escapes the skill "secure-skill" sandbox'));
      expect(response.toXmlString(), contains('Access denied'));
    });

    test('returns error observation when auxiliary file does not exist', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'my-skill'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# My Skill');

      final response = await skillsModule.executeCommand(
        'load_skill_file',
        {'name': 'my-skill', 'path': 'references/missing.md'},
      );

      expect(response.isError, isTrue);
      expect(response.errorMessage, equals('Skill or file not found'));
    });

    test('returns error when name or path parameters are missing', () async {
      final response1 = await skillsModule.executeCommand(
        'load_skill_file',
        {'name': 'my-skill'},
      );
      expect(response1.isError, isTrue);

      final response2 = await skillsModule.executeCommand(
        'load_skill_file',
        {'path': 'references/guide.md'},
      );
      expect(response2.isError, isTrue);
    });
  });
}

