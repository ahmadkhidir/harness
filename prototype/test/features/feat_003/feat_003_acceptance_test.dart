import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/skills_service.dart';
import 'package:harness/modules/skills/skills_module.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:path/path.dart' as p;

class ScriptedModelProvider extends ModelProvider {
  final List<String> script;
  final List<List<ModelMessage>> receivedHistories = [];
  final List<String?> receivedSystemInstructions = [];
  int _step = 0;

  ScriptedModelProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'test_provider',
        providerType: 'local_device',
        displayName: 'Test LLM',
        modelName: 'test-llm-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    receivedHistories.add(List.from(messages));
    receivedSystemInstructions.add(systemInstruction);
    if (_step < script.length) {
      return script[_step++];
    }
    return script.last;
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
  }
}

void main() {
  group('FEAT-003 Acceptance Tests - On-Demand Transient Skill & Sub-File Loading', () {
    late Directory tempDir;
    late AppDatabase db;
    late HarnessFileSystem fs;
    late SkillsService skillsService;
    late SkillsModule skillsModule;
    late CommandRouter router;
    late ContextBuilder contextBuilder;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('harness_feat003_test_');
      db = AppDatabase.inMemory();
      fs = await HarnessFileSystem.init(tempDir, db);
      skillsService = SkillsService(fileSystem: fs);
      skillsModule = SkillsModule(skillsService: skillsService);
      router = CommandRouter();
      router.registerModule(skillsModule);
      contextBuilder = ContextBuilder();
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Criterion 1: Lightweight catalog injected into prompt without full SKILL.md body', () {
      // Create valid skill with frontmatter and instructions
      final skillDir = Directory(p.join(fs.skillsDir.path, 'summarizer'))..createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: summarizer
description: Summarizes text into concise bullet points
version: 1.0.0
---
# Detailed Instructions
These instructions should NOT appear in the prompt catalog until loaded on-demand.
''');

      final available = skillsService.scanAvailableSkills();
      expect(available.length, equals(1));
      expect(available.first.name, equals('summarizer'));
      expect(available.first.description, equals('Summarizes text into concise bullet points'));

      final systemInstruction = contextBuilder.buildSystemInstruction(
        commands: router.allCommandDefinitions,
        storageTree: fs.formatFilesystemTree(),
        availableSkills: available,
      );

      // Verify catalog contains lightweight metadata
      expect(systemInstruction, contains('## Available Skills Catalog'));
      expect(systemInstruction, contains('- **summarizer**: Summarizes text into concise bullet points'));

      // Verify catalog does NOT contain full instructions body
      expect(systemInstruction, isNot(contains('These instructions should NOT appear in the prompt catalog')));
    });

    test('Criterion 2: load_skill returns SKILL.md content; returns error if skill not found', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'code-reviewer'))..createSync(recursive: true);
      const skillBody = '''---
name: code-reviewer
description: Reviews pull requests and flags defects
version: 2.1.0
---
# PR Review Guidelines
1. Check for dead code.
2. Verify tests.
''';
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(skillBody);

      // 1. Success case
      final successResp = await router.executeCall(
        SystemCall(command: 'load_skill', parameters: {'name': 'code-reviewer'}),
      );

      expect(successResp.isSuccess, isTrue);
      expect(successResp.command, equals('load_skill'));
      expect(successResp.data, equals(skillBody));
      expect(successResp.toXmlString(), contains('<system_response command="load_skill"'));
      expect(successResp.toXmlString(), contains('PR Review Guidelines'));

      // 2. Not found error case
      final missingResp = await router.executeCall(
        SystemCall(command: 'load_skill', parameters: {'name': 'nonexistent-skill'}),
      );

      expect(missingResp.isSuccess, isFalse);
      expect(missingResp.errorMessage, contains('Skill or file not found'));
    });

    test('Criterion 3: load_skill_file loads auxiliary files in references, assets, and scripts', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'code-reviewer'))..createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: code-reviewer
description: Reviews pull requests
---
# Reviewer
''');

      // Create auxiliary files in references/, assets/, and scripts/
      final refDir = Directory(p.join(skillDir.path, 'references'))..createSync(recursive: true);
      File(p.join(refDir.path, 'checklist.md')).writeAsStringSync('Checklist: Lint, Tests, Security.');

      final scriptDir = Directory(p.join(skillDir.path, 'scripts'))..createSync(recursive: true);
      File(p.join(scriptDir.path, 'analyze.py')).writeAsStringSync('print("Running analysis")');

      // Load reference file
      final refResp = await router.executeCall(
        SystemCall(command: 'load_skill_file', parameters: {
          'name': 'code-reviewer',
          'path': 'references/checklist.md',
        }),
      );
      expect(refResp.isSuccess, isTrue);
      expect(refResp.data, equals('Checklist: Lint, Tests, Security.'));

      // Load script file
      final scriptResp = await router.executeCall(
        SystemCall(command: 'load_skill_file', parameters: {
          'name': 'code-reviewer',
          'path': 'scripts/analyze.py',
        }),
      );
      expect(scriptResp.isSuccess, isTrue);
      expect(scriptResp.data, equals('print("Running analysis")'));

      // Missing auxiliary file returns structured error
      final missingResp = await router.executeCall(
        SystemCall(command: 'load_skill_file', parameters: {
          'name': 'code-reviewer',
          'path': 'references/missing.md',
        }),
      );
      expect(missingResp.isSuccess, isFalse);
      expect(missingResp.errorMessage, contains('Skill or file not found'));
    });

    test('Criterion 4: Transient working context: loaded skill used during turn and evicted upon task completion', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'summarizer'))..createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: summarizer
description: Summarizes text
---
# Summarizer Rule
Always start summaries with [SUMMARY].
''');

      final model = ScriptedModelProvider([
        // Turn 1: Model sees summarizer in available_skills catalog and calls load_skill
        '''
Scratchpad: User wants a summary. I will load the summarizer skill first.
<system_call>
{"command": "load_skill", "parameters": {"name": "summarizer"}}
</system_call>
''',
        // Turn 2: Model observes skill instructions in dialogue history and delivers final message
        '''
<system_call>
{"command": "send_ui_message", "parameters": {"message": "[SUMMARY] The meeting covered Q3 targets."}}
</system_call>
''',
      ]);

      final engine = HarnessEngine(
        modelProvider: model,
        router: router,
        contextBuilder: contextBuilder,
        skillsService: skillsService,
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Please summarize the Q3 meeting notes.',
        sessionId: 'session_acceptance_1',
      )) {
        events.add(event);
      }

      // Verify execution flow
      expect(events.whereType<EngineTurnStarted>().length, equals(1));
      expect(events.whereType<EngineSystemCallStarted>().length, equals(1));
      expect(events.whereType<EngineSystemCallFinished>().length, equals(1));

      final completedEvent = events.whereType<EngineTurnCompleted>().first;
      expect(completedEvent.turn.text, equals('[SUMMARY] The meeting covered Q3 targets.'));

      // Verify that during Turn 2, the model received the loaded skill in its transient history
      expect(model.receivedHistories.length, equals(2));
      final turn2History = model.receivedHistories[1];
      final observationMessage = turn2History.firstWhere((m) => m.role == 'user' && m.content.contains('<system_response'));
      expect(observationMessage.content, contains('Always start summaries with [SUMMARY].'));

      // Verify eviction: the final completed Turn persisted in session contains ONLY the explicit message,
      // and NOT the transient loaded skill content
      expect(completedEvent.turn.text, isNot(contains('<system_response')));
      expect(completedEvent.turn.text, isNot(contains('Summarizer Rule')));
    });

    test('Criterion 5: Path traversal attack blocked with access-denied security error observation', () async {
      final skillDir = Directory(p.join(fs.skillsDir.path, 'summarizer'))..createSync(recursive: true);
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: summarizer
description: Summarizes text
---
# Summarizer
''');

      // Attempt path traversal with directory escape
      final traversalResp = await router.executeCall(
        SystemCall(command: 'load_skill_file', parameters: {
          'name': 'summarizer',
          'path': '../../storage/secret.txt',
        }),
      );

      expect(traversalResp.isSuccess, isFalse);
      expect(traversalResp.errorMessage, contains('Access denied'));
      expect(traversalResp.errorMessage, contains('escapes the skill "summarizer" sandbox'));
      expect(traversalResp.toXmlString(), contains('<system_response command="load_skill_file"'));
      expect(traversalResp.toXmlString(), contains('Access denied'));
    });

    test('Criterion 6: Malformed skills (missing SKILL.md or invalid frontmatter) excluded from prompt catalog', () {
      // 1. Valid skill
      final validDir = Directory(p.join(fs.skillsDir.path, 'valid-skill'))..createSync(recursive: true);
      File(p.join(validDir.path, 'SKILL.md')).writeAsStringSync('''---
name: valid-skill
description: A perfectly valid skill
version: 1.0.0
---
# Valid
''');

      // 2. Skill folder without SKILL.md
      Directory(p.join(fs.skillsDir.path, 'empty-skill-dir')).createSync(recursive: true);

      // 3. Skill with completely empty SKILL.md
      final blankDir = Directory(p.join(fs.skillsDir.path, 'blank-skill'))..createSync(recursive: true);
      File(p.join(blankDir.path, 'SKILL.md')).writeAsStringSync('   \n  ');

      final available = skillsService.scanAvailableSkills();

      // Only valid skill is in prompt catalog
      expect(available.length, equals(1));
      expect(available.first.name, equals('valid-skill'));

      final systemInstruction = contextBuilder.buildSystemInstruction(
        commands: router.allCommandDefinitions,
        storageTree: fs.formatFilesystemTree(),
        availableSkills: available,
      );

      expect(systemInstruction, contains('- **valid-skill**: A perfectly valid skill'));
      expect(systemInstruction, isNot(contains('empty-skill-dir')));
      expect(systemInstruction, isNot(contains('blank-skill')));
    });
  });
}
