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
  /// - Zero Thinking Leakage delivery rules (`send_message` and `send_a2ui`)
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
        'You may emit MULTIPLE `<system_call>` tags in a single turn. The engine will execute them concurrently in parallel.');
    buffer.writeln();

    buffer.writeln('## Zero Thinking Leakage Rule');
    buffer.writeln(
        'Any intermediate scratchpad text emitted alongside system calls is treated as internal reasoning and will NOT be shown to the user.');
    buffer.writeln(
        'To deliver a final user-facing response, you MUST use one of the two delivery commands:');
    buffer.writeln(
        '1. `<system_call>{"command": "send_message", "parameters": {"text": "<markdown>"}}</system_call>`');
    buffer.writeln(
        '2. `<system_call>{"command": "send_a2ui", "parameters": {"messages": [...]}}</system_call>`');
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
