import 'dart:convert';
import '../models/system_call.dart';

/// Container representing the parsed output of an LLM turn.
class ParsedModelOutput {
  /// Structured system calls requiring module execution.
  final List<SystemCall> systemCalls;

  /// Intermediate reasoning or scratchpad monologue extracted outside `<system_call>` blocks.
  /// Suppressed from the user-facing chat UI according to the Zero Thinking Leakage rule.
  final String scratchpadText;

  /// Explicit user-facing Markdown message delivered via `send_message` or companion text.
  final String? explicitTextMessage;

  /// Explicit A2UI payload delivered via `send_a2ui`.
  final Map<String, dynamic>? explicitA2UIPayload;

  const ParsedModelOutput({
    required this.systemCalls,
    required this.scratchpadText,
    this.explicitTextMessage,
    this.explicitA2UIPayload,
  });

  /// True if the model output contains callable system calls.
  bool get hasSystemCalls => systemCalls.isNotEmpty;

  /// True if the model explicitly emitted a delivery command (`send_message` or `send_a2ui`).
  bool get hasExplicitDelivery =>
      explicitTextMessage != null || explicitA2UIPayload != null;
}

/// Robust parser for extracting `<system_call>` XML/JSON blocks from model generation.
///
/// Implements Zero Thinking Leakage by separating internal monologue reasoning from
/// explicit user delivery commands (`send_message` and `send_a2ui`).
class SystemCallParser {
  static final RegExp _systemCallRegex = RegExp(
    r'<system_call>\s*([\s\S]*?)\s*<\/system_call>',
    multiLine: true,
  );

  /// Parses the raw string response from an LLM.
  static ParsedModelOutput parse(String rawOutput) {
    final List<SystemCall> calls = [];
    final StringBuffer scratchpad = StringBuffer();
    String? explicitText;
    Map<String, dynamic>? explicitA2UI;

    int lastIndex = 0;

    for (final match in _systemCallRegex.allMatches(rawOutput)) {
      // Any text between or before <system_call> tags is internal scratchpad monologue.
      // Separate it so it can be logged without leaking into the user-facing chat bubble.
      if (match.start > lastIndex) {
        final betweenText = rawOutput.substring(lastIndex, match.start).trim();
        if (betweenText.isNotEmpty) {
          scratchpad.writeln(betweenText);
        }
      }

      final jsonContent = match.group(1)?.trim();
      if (jsonContent != null && jsonContent.isNotEmpty) {
        try {
          final decoded = json.decode(jsonContent);
          if (decoded is Map<String, dynamic>) {
            final cmd = decoded['command'] as String?;
            final params = decoded['parameters'] != null
                ? Map<String, dynamic>.from(decoded['parameters'] as Map)
                : <String, dynamic>{};

            if (cmd != null) {
              if (cmd == 'send_message') {
                explicitText = params['text'] as String? ?? '';
              } else if (cmd == 'send_a2ui') {
                explicitA2UI = params;
                explicitText = params['text'] as String?;
              } else {
                calls.add(SystemCall(command: cmd, parameters: params));
              }
            }
          }
        } catch (_) {
          // If JSON decode failed, create an error system call so model gets immediate self-correction feedback
          calls.add(SystemCall(
            command: 'malformed_json_error',
            parameters: {
              'raw': jsonContent,
              'error': 'Malformed JSON inside <system_call> block.',
            },
          ));
        }
      }

      lastIndex = match.end;
    }

    // Capture any trailing text after the final system call
    if (lastIndex < rawOutput.length) {
      final trailingText = rawOutput.substring(lastIndex).trim();
      if (trailingText.isNotEmpty) {
        // Fallback: If no system calls and no delivery commands exist in the entire output,
        // treat the raw text as a direct message so simple text-only LLMs still function.
        if (calls.isEmpty && explicitText == null && explicitA2UI == null) {
          explicitText = trailingText;
        } else {
          scratchpad.writeln(trailingText);
        }
      }
    }

    return ParsedModelOutput(
      systemCalls: calls,
      scratchpadText: scratchpad.toString().trim(),
      explicitTextMessage: explicitText,
      explicitA2UIPayload: explicitA2UI,
    );
  }
}
