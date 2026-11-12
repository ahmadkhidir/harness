import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/models/models.dart';

void main() {
  group('ContextBuilder - Prompt Construction', () {
    test('renders consistent <system_call> syntax, excludes skill version, and avoids redundant command instructions in skills section', () {
      final builder = ContextBuilder();
      final commands = [
        CommandDefinition(
          command: 'grep',
          description: 'Regex search',
          parametersSchema: const {'type': 'object'},
        ),
        CommandDefinition(
          command: 'load_skill',
          description: 'Load skill instructions',
          parametersSchema: const {'type': 'object'},
        ),
      ];
      final skills = [
        SkillMetadata(
          name: 'summarizer',
          description: 'Extracts highlights and action items from text.',
          version: '1.2.3',
        ),
      ];

      final instruction = builder.buildSystemInstruction(
        commands: commands,
        availableSkills: skills,
        storageTree: 'storage/\n└── notes.txt',
        currentTime: DateTime.utc(2026, 10, 30, 3, 0, 0),
      );

      // Verify consistent <system_call> format
      expect(
        instruction.contains(
            '`<system_call>{"command": "<command_name>", "parameters": { ... }}</system_call>`'),
        isTrue,
      );

      // Verify the single delivery command format
      expect(
        instruction.contains(
            '`<system_call>{"command": "send_ui_message", "parameters": {"message": "<your markdown response>"}}</system_call>`'),
        isTrue,
      );
      expect(instruction.contains('send_a2ui'), isFalse);
      expect(instruction.contains('load_a2ui_catalog'), isFalse);

      // Verify skill format does NOT include version
      expect(
        instruction.contains('- **summarizer**: Extracts highlights and action items from text.'),
        isTrue,
      );
      expect(instruction.contains('v1.2.3'), isFalse);

      // Verify redundant manual call instructions are omitted from the skills section
      expect(
        instruction.contains('To inspect skill instructions or auxiliary files'),
        isFalse,
      );
    });
  });
}
