import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/skills_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late HarnessFileSystem fs;
  late SkillsService skillsService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('harness_skills_test_');
    db = AppDatabase.inMemory();
    fs = await HarnessFileSystem.init(tempDir, db);
    skillsService = SkillsService(fileSystem: fs);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SkillsService frontmatter parsing', () {
    test('parses valid YAML frontmatter with name, description, version', () {
      const content = '''
---
name: code-reviewer
description: Reviews pull requests and flags defects
version: 1.2.0
---
# Code Reviewer
Instructions here.
''';

      final meta = SkillsService.parseFrontmatter(content, 'code-reviewer');
      expect(meta, isNotNull);
      expect(meta!.name, equals('code-reviewer'));
      expect(meta.description, equals('Reviews pull requests and flags defects'));
      expect(meta.version, equals('1.2.0'));
    });

    test('parses YAML frontmatter with quoted values', () {
      const content = '''
---
name: "data-analyzer"
description: 'Processes CSV files and outputs summaries'
version: "2.0.1"
---
Instructions.
''';

      final meta = SkillsService.parseFrontmatter(content, 'data-analyzer');
      expect(meta, isNotNull);
      expect(meta!.name, equals('data-analyzer'));
      expect(meta.description, equals('Processes CSV files and outputs summaries'));
      expect(meta.version, equals('2.0.1'));
    });

    test('falls back to markdown header and paragraph when YAML frontmatter is absent', () {
      const content = '''
# Web Scraper
Extracts content from web pages using headless browsers.

## How to use
Run the scrape command.
''';

      final meta = SkillsService.parseFrontmatter(content, 'web-scraper');
      expect(meta, isNotNull);
      expect(meta!.name, equals('web-scraper'));
      expect(meta.description, equals('Extracts content from web pages using headless browsers.'));
      expect(meta.version, equals('1.0.0'));
    });

    test('sanitizes non-kebab-case names into valid kebab-case', () {
      const content = '''
---
name: "My Awesome Tool 2.0"
description: "Great tool"
---
''';

      final meta = SkillsService.parseFrontmatter(content, 'my-tool');
      expect(meta, isNotNull);
      expect(meta!.name, equals('my-awesome-tool-2-0'));
    });
  });

  group('SkillsService scanning and exclusion', () {
    test('scanAvailableSkills excludes malformed skill directories missing SKILL.md', () async {
      // 1. Create valid skill 'summarizer'
      final summarizerDir = Directory(p.join(fs.skillsDir.path, 'summarizer'));
      await summarizerDir.create(recursive: true);
      final validSkillMd = File(p.join(summarizerDir.path, 'SKILL.md'));
      await validSkillMd.writeAsString('''
---
name: summarizer
description: Summarizes lengthy documents into concise bullet points
version: 1.0.0
---
# Summarizer
''');

      // 2. Create malformed skill folder missing SKILL.md
      final malformedDir = Directory(p.join(fs.skillsDir.path, 'broken-skill'));
      await malformedDir.create(recursive: true);
      final randomFile = File(p.join(malformedDir.path, 'README.txt'));
      await randomFile.writeAsString('Not a skill');

      final available = skillsService.scanAvailableSkills();
      expect(available.length, equals(1));
      expect(available.first.name, equals('summarizer'));
      expect(available.any((s) => s.name == 'broken-skill'), isFalse);
    });

    test('scanAllSkillPackages flags malformed packages with isMalformed: true', () async {
      // 1. Create valid skill
      final validDir = Directory(p.join(fs.skillsDir.path, 'valid-skill'));
      await validDir.create(recursive: true);
      await File(p.join(validDir.path, 'SKILL.md')).writeAsString('''
---
name: valid-skill
description: Valid skill
version: 1.0.0
---
Content
''');

      // 2. Create malformed skill
      final brokenDir = Directory(p.join(fs.skillsDir.path, 'missing-md'));
      await brokenDir.create(recursive: true);

      final packages = skillsService.scanAllSkillPackages();
      expect(packages.length, equals(2));

      final validPkg = packages.firstWhere((p) => p.directoryName == 'valid-skill');
      expect(validPkg.isMalformed, isFalse);
      expect(validPkg.displayName, equals('valid-skill'));

      final brokenPkg = packages.firstWhere((p) => p.directoryName == 'missing-md');
      expect(brokenPkg.isMalformed, isTrue);
      expect(brokenPkg.malformedReason, contains('Missing SKILL.md'));
    });

    test('scanAllSkillPackages counts auxiliary files in subdirectories', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'doc-gen'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('''
---
name: doc-gen
description: Generates documentation
version: 1.0.0
---
''');

      // Add auxiliary files in references/ and assets/
      final refDir = Directory(p.join(skillDir.path, 'references'));
      await refDir.create(recursive: true);
      await File(p.join(refDir.path, 'guide.md')).writeAsString('Guide');

      final assetDir = Directory(p.join(skillDir.path, 'assets'));
      await assetDir.create(recursive: true);
      await File(p.join(assetDir.path, 'template.json')).writeAsString('{}');

      final packages = skillsService.scanAllSkillPackages();
      final pkg = packages.firstWhere((p) => p.directoryName == 'doc-gen');
      expect(pkg.subFileCount, equals(2));
      expect(pkg.auxiliaryFiles, contains('references/guide.md'));
      expect(pkg.auxiliaryFiles, contains('assets/template.json'));
    });
  });

  group('SkillsService reading and security', () {
    test('readSkill returns SKILL.md content for existing skill', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'formatter'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# Formatter Instructions');

      final content = skillsService.readSkill('formatter');
      expect(content, equals('# Formatter Instructions'));
    });

    test('readSkill returns null for non-existent skill', () {
      final content = skillsService.readSkill('non-existent');
      expect(content, isNull);
    });

    test('readSkillFile reads auxiliary file correctly', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'coder'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# Coder');

      final scriptsDir = Directory(p.join(skillDir.path, 'scripts'));
      await scriptsDir.create(recursive: true);
      await File(p.join(scriptsDir.path, 'lint.sh')).writeAsString('#!/bin/bash\necho "linting"');

      final content = skillsService.readSkillFile('coder', 'scripts/lint.sh');
      expect(content, equals('#!/bin/bash\necho "linting"'));
    });

    test('readSkillFile throws SecurityException on path traversal attempt', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'sandbox-test'));
      await skillDir.create(recursive: true);
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# Sandbox');

      expect(
        () => skillsService.readSkillFile('sandbox-test', '../../secret.txt'),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}

