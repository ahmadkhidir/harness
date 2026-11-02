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
///
/// Gracefully handles unclosed `<system_call>` tags, truncated JSON, and ensures
/// raw `<system_call>` XML syntax never leaks into user-facing chat bubbles.
class SystemCallParser {
  static const String _openTag = '<system_call>';
  static const String _closeTag = '</system_call>';

  /// Parses the raw string response from an LLM.
  static ParsedModelOutput parse(String rawOutput) {
    final List<SystemCall> calls = [];
    final StringBuffer scratchpad = StringBuffer();
    String? explicitText;
    Map<String, dynamic>? explicitA2UI;

    int cursor = 0;

    while (cursor < rawOutput.length) {
      final startIndex = rawOutput.indexOf(_openTag, cursor);
      if (startIndex == -1) {
        // No more <system_call> tags
        final trailingText = rawOutput.substring(cursor).trim();
        if (trailingText.isNotEmpty) {
          // Fallback: If no system calls and no delivery commands exist in the entire output,
          // treat the raw text as a direct message so simple text-only LLMs still function.
          // CRITICAL: Ensure raw <system_call> tags never leak into explicit text.
          if (calls.isEmpty && explicitText == null && explicitA2UI == null) {
            if (!trailingText.contains(_openTag)) {
              explicitText = trailingText;
            }
          } else {
            scratchpad.writeln(trailingText);
          }
        }
        break;
      }

      // Any text between or before <system_call> tags is internal scratchpad monologue.
      if (startIndex > cursor) {
        final betweenText = rawOutput.substring(cursor, startIndex).trim();
        if (betweenText.isNotEmpty) {
          scratchpad.writeln(betweenText);
        }
      }

      final contentStart = startIndex + _openTag.length;
      final endIndex = rawOutput.indexOf(_closeTag, contentStart);

      String jsonContent;
      if (endIndex != -1) {
        // Standard closed <system_call>...</system_call> block
        jsonContent = rawOutput.substring(contentStart, endIndex).trim();
        cursor = endIndex + _closeTag.length;
      } else {
        // Unclosed <system_call> extending to the end of output
        jsonContent = rawOutput.substring(contentStart).trim();
        cursor = rawOutput.length;
      }

      if (jsonContent.isNotEmpty) {
        _processSystemCallBlock(
          jsonContent,
          calls: calls,
          onTextMessage: (text) => explicitText = text,
          onA2UI: (payload, text) {
            explicitA2UI = payload;
            if (text != null) explicitText = text;
          },
        );
      }
    }

    return ParsedModelOutput(
      systemCalls: calls,
      scratchpadText: scratchpad.toString().trim(),
      explicitTextMessage: explicitText,
      explicitA2UIPayload: explicitA2UI,
    );
  }

  /// Parses and processes a single `<system_call>` JSON payload.
  static void _processSystemCallBlock(
    String jsonContent, {
    required List<SystemCall> calls,
    required void Function(String) onTextMessage,
    required void Function(Map<String, dynamic>, String?) onA2UI,
  }) {
    // 1. First try parsing or repairing the JSON structure
    final decoded = _tryRepairAndDecodeJson(jsonContent);
    if (decoded != null) {
      final cmd = decoded['command'] as String?;
      final params = decoded['parameters'] != null
          ? Map<String, dynamic>.from(decoded['parameters'] as Map)
          : <String, dynamic>{};

      if (cmd != null) {
        if (cmd == 'send_message') {
          onTextMessage(params['text'] as String? ?? '');
          return;
        } else if (cmd == 'send_a2ui') {
          onA2UI(params, params['text'] as String?);
          return;
        } else {
          calls.add(SystemCall(command: cmd, parameters: params));
          return;
        }
      }
    }

    // 2. Resilient fallback for unclosed send_message where JSON couldn't be cleanly parsed
    final sendMsgMatch = RegExp(
      r'"command"\s*:\s*"send_message"[\s\S]*?"text"\s*:\s*"(.*)',
      dotAll: true,
    ).firstMatch(jsonContent);

    if (sendMsgMatch != null) {
      var text = sendMsgMatch.group(1) ?? '';
      // Strip trailing JSON closing braces/quotes if present
      text = text.replaceAll(RegExp(r'"\s*\}*\s*$'), '');
      text = _unescapeJsonString(text);
      onTextMessage(text);
      return;
    }

    // 3. If unrecoverable, record a malformed_json_error system call
    calls.add(SystemCall(
      command: 'malformed_json_error',
      parameters: {
        'raw': jsonContent,
        'error': 'Malformed or unclosed JSON inside <system_call> block.',
      },
    ));
  }

  /// Attempts direct JSON decode; if it fails, attempts structural repair
  /// by closing unclosed strings, brackets, and braces.
  static Map<String, dynamic>? _tryRepairAndDecodeJson(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    try {
      final trimmed = text.trim();
      final buffer = StringBuffer(trimmed);
      bool inString = false;
      bool isEscaped = false;
      final stack = <String>[];

      for (int i = 0; i < trimmed.length; i++) {
        final char = trimmed[i];
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == r'\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = !inString;
          continue;
        }
        if (!inString) {
          if (char == '{') {
            stack.add('}');
          } else if (char == '[') {
            stack.add(']');
          } else if (char == '}' || char == ']') {
            if (stack.isNotEmpty && stack.last == char) {
              stack.removeLast();
            }
          }
        }
      }

      if (inString) {
        buffer.write('"');
      }

      while (stack.isNotEmpty) {
        buffer.write(stack.removeLast());
      }

      final repaired = buffer.toString();
      final decoded = json.decode(repaired);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    return null;
  }

  /// Unescapes common JSON control sequences in salvaged text.
  static String _unescapeJsonString(String input) {
    return input
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', r'\');
  }
}
