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
/// Resilient against:
/// - Markdown code fences (` ```json ` or ` ```xml `) inside `<system_call>`.
/// - Trailing commas before `}` or `]`.
/// - Unclosed `<system_call>` tags, unclosed strings, and unbalanced brackets.
/// - Unescaped newlines/tabs inside string literals.
/// - Automatically generates visual syntax error snippets with exact line and column locations.
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
            if (text != null && text.isNotEmpty) explicitText = text;
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
    // 1. Clean and decode or repair the JSON structure
    final decodeResult = _tryRepairAndDecodeJson(jsonContent);
    final decoded = decodeResult.decoded;

    if (decoded != null) {
      final cmd = decoded['command'] as String?;
      final params = decoded['parameters'] != null && decoded['parameters'] is Map
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

    // 2. Resilient fallback for unclosed or truncated send_message
    final sendMsgMatch = RegExp(
      r'"command"\s*:\s*"send_message"[\s\S]*?"text"\s*:\s*"(.*)',
      dotAll: true,
    ).firstMatch(jsonContent);

    if (sendMsgMatch != null) {
      var text = sendMsgMatch.group(1) ?? '';
      text = text.replaceAll(RegExp(r'"\s*\}*\s*$'), '');
      text = _unescapeJsonString(text);
      onTextMessage(text);
      return;
    }

    // 3. Resilient fallback for send_a2ui with minor JSON truncation or syntax quirk
    if (jsonContent.contains('"send_a2ui"')) {
      final salvagedA2UI = _trySalvageA2UIPayload(jsonContent);
      if (salvagedA2UI != null) {
        onA2UI(salvagedA2UI, salvagedA2UI['text'] as String?);
        return;
      }
    }

    // 4. If unrecoverable, record a malformed_json_error with exact line, column, and snippet
    final formattedError = decodeResult.formattedError ??
        'Malformed or unclosed JSON inside <system_call> block.';

    calls.add(SystemCall(
      command: 'malformed_json_error',
      parameters: {
        'raw': jsonContent,
        'error': formattedError,
        'line': decodeResult.errorLine,
        'column': decodeResult.errorColumn,
      },
    ));
  }

  /// Attempts direct JSON decode and multi-pass structural repair.
  ///
  /// Passes:
  /// 1. Strip markdown fences (```json or ```xml).
  /// 2. Direct decode.
  /// 3. Strip trailing commas and comments.
  /// 4. Balance unclosed quotes, brackets, and braces.
  /// 5. Captures syntax error location and visual context snippet.
  static _JsonDecodeResult _tryRepairAndDecodeJson(String text) {
    // Pass 1: Strip markdown code blocks / fences if model wrapped them
    var cleaned = _stripMarkdownFences(text);

    // Pass 2: Direct standard JSON decode
    try {
      final direct = json.decode(cleaned);
      if (direct is Map<String, dynamic>) {
        return _JsonDecodeResult(decoded: direct);
      }
    } catch (_) {}

    // Pass 3: Sanitize trailing commas, comments, and unescaped characters
    cleaned = _sanitizeJsonString(cleaned);
    try {
      final sanitized = json.decode(cleaned);
      if (sanitized is Map<String, dynamic>) {
        return _JsonDecodeResult(decoded: sanitized);
      }
    } catch (_) {}

    // Pass 4: Balance unclosed strings, brackets, and braces
    FormatException? lastException;
    try {
      final repaired = _balanceBracketsAndQuotes(cleaned);
      final repairedDecoded = json.decode(repaired);
      if (repairedDecoded is Map<String, dynamic>) {
        return _JsonDecodeResult(decoded: repairedDecoded);
      }
    } on FormatException catch (e) {
      lastException = e;
    } catch (_) {}

    // Pass 5: Produce visual syntax error snippet with exact line and column
    if (lastException != null) {
      final snippet = _formatSyntaxError(cleaned, lastException);
      final offset = lastException.offset ?? 0;
      final pos = _calculateLineCol(cleaned, offset);
      return _JsonDecodeResult(
        formattedError: snippet,
        errorLine: pos.$1,
        errorColumn: pos.$2,
      );
    }

    return const _JsonDecodeResult();
  }

  /// Strips markdown fences (e.g. ```json ... ``` or ```xml ... ```).
  static String _stripMarkdownFences(String input) {
    var s = input.trim();
    // Strip leading fence
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    }
    // Strip trailing fence
    if (s.endsWith('```')) {
      s = s.substring(0, s.length - 3).trim();
    }
    return s.trim();
  }

  /// Sanitizes comments and trailing commas before closing braces/brackets.
  static String _sanitizeJsonString(String input) {
    var s = input;

    // Remove single line comments: // ...
    s = s.replaceAll(RegExp(r'(?<!:)\/\/.*$', multiLine: true), '');

    // Remove trailing commas before } or ]
    s = s.replaceAllMapped(RegExp(r',\s*([\}\]])'), (m) => m.group(1)!);

    return s;
  }

  /// Closes unclosed quotes and balances open brackets `[` and braces `{`.
  static String _balanceBracketsAndQuotes(String text) {
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

    // Once more remove trailing commas that might have ended up before added closing braces
    return buffer.toString().replaceAllMapped(RegExp(r',\s*([\}\]])'), (m) => m.group(1)!);
  }

  /// Salvages a `send_a2ui` payload by extracting companion text and messages list.
  static Map<String, dynamic>? _trySalvageA2UIPayload(String jsonContent) {
    try {
      final textMatch = RegExp(r'"text"\s*:\s*"(.*?)(?<!\\)"').firstMatch(jsonContent);
      final companionText = textMatch != null ? _unescapeJsonString(textMatch.group(1)!) : null;

      // Extract messages array: "messages"\s*:\s*\[ ... \]
      final messagesIdx = jsonContent.indexOf('"messages"');
      if (messagesIdx != -1) {
        final bracketStart = jsonContent.indexOf('[', messagesIdx);
        if (bracketStart != -1) {
          final arrayText = _extractBalancedArray(jsonContent, bracketStart);
          if (arrayText != null) {
            final cleanedArray = _sanitizeJsonString(arrayText);
            final balancedArray = _balanceBracketsAndQuotes(cleanedArray);
            final decodedMessages = json.decode(balancedArray);
            if (decodedMessages is List) {
              final payload = <String, dynamic>{'messages': decodedMessages};
              if (companionText != null) payload['text'] = companionText;
              return payload;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _extractBalancedArray(String text, int startIdx) {
    int depth = 0;
    bool inString = false;
    bool isEscaped = false;

    for (int i = startIdx; i < text.length; i++) {
      final char = text[i];
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
        if (char == '[') depth++;
        if (char == ']') {
          depth--;
          if (depth == 0) {
            return text.substring(startIdx, i + 1);
          }
        }
      }
    }

    // Unclosed array: return text from startIdx
    return text.substring(startIdx);
  }

  /// Formats a visual syntax error snippet pointing with `^` to the exact line and column.
  static String _formatSyntaxError(String rawText, FormatException ex) {
    final offset = ex.offset ?? 0;
    final safeOffset = offset.clamp(0, rawText.length);
    final pos = _calculateLineCol(rawText, safeOffset);
    final line = pos.$1;
    final col = pos.$2;

    int lineStart = 0;
    int currentLine = 1;
    for (int i = 0; i < rawText.length; i++) {
      if (currentLine == line) {
        lineStart = i;
        break;
      }
      if (rawText[i] == '\n') currentLine++;
    }

    int lineEnd = rawText.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = rawText.length;

    final lineContent = rawText.substring(lineStart, lineEnd).trimRight();
    final colPointer = (col - 1).clamp(0, lineContent.length);
    final pointer = ' ' * colPointer + '^';

    return 'JSON Syntax Error at line $line, column $col:\n'
        '  $line | $lineContent\n'
        '  ${' ' * line.toString().length} | $pointer\n'
        '${ex.message}';
  }

  static (int, int) _calculateLineCol(String text, int offset) {
    int line = 1;
    int col = 1;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return (line, col);
  }

  static String _unescapeJsonString(String input) {
    return input
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', r'\');
  }
}

class _JsonDecodeResult {
  final Map<String, dynamic>? decoded;
  final String? formattedError;
  final int? errorLine;
  final int? errorColumn;

  const _JsonDecodeResult({
    this.decoded,
    this.formattedError,
    this.errorLine,
    this.errorColumn,
  });
}
