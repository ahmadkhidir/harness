import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/command_definition.dart';
import '../models/skill_metadata.dart';

/// Context assembler responsible for compiling system prompts and working memory.
///
/// Implements the context assembly pipeline specified in `docs/Harness/architecture.md`.
class ContextBuilder {
  /// Builds the authoritative system prompt injected into the LLM context.
  ///
  /// Combines:
  /// - Current local date-time with timezone offset
  /// - Autonomous tool calling instructions using standard `<system_call>` tags
  /// - Zero Thinking Leakage delivery rule (`send_ui_message`)
  /// - Registered command definitions and JSON schemas
  /// - Installed skills index (`available_skills`)
  /// - Storage directory tree map
  String buildSystemInstruction({
    required List<CommandDefinition> commands,
    List<SkillMetadata> availableSkills = const [],
    String storageTree = '<filesystem>\nprimary/\n  (empty)\n</filesystem>',
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final formattedTime = DateFormat("yyyy-MM-dd'T'HH:mm:ssZZZZZ").format(now);

    final buffer = StringBuffer();
    buffer.writeln('# Harness Autonomous Agent Runtime');
    buffer.writeln('Current Local Time: $formattedTime');
    buffer.writeln();

    buffer.writeln('## Autonomous Execution Loop & Tool Protocol');
    buffer.writeln(
        'You are Harness, an autonomous agent running on a mobile device. You execute complex tasks autonomously using multi-turn tool loops.');
    buffer.writeln(
        'To call tools, emit one or more `<system_call>` tags with JSON payloads:');
    buffer.writeln(
        '`<system_call>{"command": "<command_name>", "parameters": { ... }}</system_call>`');
    buffer.writeln(
        'Do NOT use DSML, native function-call markup, or any other tool syntax. Only the `<system_call>` format is accepted.');
    buffer.writeln(
        'You may emit MULTIPLE `<system_call>` tags in a single turn. The engine will execute them concurrently in parallel.');
    buffer.writeln();

    buffer.writeln('## Delivery Protocol');
    buffer.writeln(
        'Any intermediate scratchpad text emitted alongside system calls is internal reasoning and is not shown to the user.');
    buffer.writeln(
        'Every turn must end with a non-empty `send_ui_message` call:');
    buffer.writeln(
        '`<system_call>{"command": "send_ui_message", "parameters": {"message": "<your markdown response>"}}</system_call>`');
    buffer.writeln();

    buffer.writeln('## Composer Tags');
    buffer.writeln(
        '- A token like `/skill-name` refers to an installed skill. Call `load_skill` for it before proceeding.');
    buffer.writeln(
        '- A token like `@primary/path` or `@<mount>/path` is a virtual storage path. Use `read_file` or `list_directory` as needed.');
    buffer.writeln();

    buffer.writeln('## Available Commands');
    for (final cmd in commands) {
      buffer.writeln('- **${cmd.command}**: ${cmd.description}');
      buffer.writeln('  Schema: ${json.encode(cmd.parametersSchema)}');
    }
    buffer.writeln();

    buffer.writeln('## Available Skills Catalog');
    if (availableSkills.isEmpty) {
      buffer.writeln('(No custom skills installed)');
    } else {
      for (final skill in availableSkills) {
        buffer.writeln('- **${skill.name}**: ${skill.description}');
      }
    }
    buffer.writeln();

    buffer.writeln('## Local Sandboxed Storage Map');
    buffer.writeln(storageTree);

    return buffer.toString().trim();
  }
}
