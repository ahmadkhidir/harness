import 'dart:convert';
import '../models/system_call.dart';

/// Container representing the parsed output of an LLM turn.
class ParsedModelOutput {
  /// Structured system calls requiring module execution.
  final List<SystemCall> systemCalls;

  /// Intermediate reasoning or scratchpad monologue extracted outside `<system_call>` blocks.
  /// Suppressed from the user-facing chat UI according to the Zero Thinking Leakage rule.
  final String scratchpadText;

  /// Explicit user-facing Markdown message delivered through `send_ui_message`
  /// or as the companion text of an A2UI delivery.
  final String? explicitTextMessage;

  /// Explicit A2UI message list delivered through `send_ui_message`.
  final Map<String, dynamic>? explicitA2UIPayload;

  const ParsedModelOutput({
    required this.systemCalls,
    required this.scratchpadText,
    this.explicitTextMessage,
    this.explicitA2UIPayload,
  });

  /// True if the model output contains callable system calls.
  bool get hasSystemCalls => systemCalls.isNotEmpty;

  /// True if the model explicitly emitted a `send_ui_message` delivery.
  ///
  /// Empty or whitespace-only text is treated as a missing delivery: accepting it
  /// would persist a blank agent turn instead of letting the engine retry.
  bool get hasExplicitDelivery =>
      (explicitTextMessage?.trim().isNotEmpty ?? false) ||
      explicitA2UIPayload != null;
}

/// Robust parser for extracting `<system_call>` XML/JSON blocks from model generation.
///
/// Implements Zero Thinking Leakage by separating internal monologue reasoning from
/// explicit user delivery commands (`send_ui_message`).
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

  // DeepSeek models often ignore the requested <system_call> protocol and
  // emit their native DSML tool-call dialect instead. Deployments vary between
  // single/double fullwidth bars, ASCII pipes, and wrapper names such as
  // `tool_calls`, `calls`, or `function_calls`, so these matchers are
  // deliberately lenient and key only on the stable structural words.
  static final RegExp _dsmlInvoke = RegExp(
    r'<[^>]*DSML[^>]*invoke\s+name\s*=\s*"([^"]+)"[^>]*>([\s\S]*?)</[^>]*DSML[^>]*invoke\s*>',
    caseSensitive: false,
  );
  static final RegExp _dsmlParameter = RegExp(
    r'<[^>]*DSML[^>]*parameter\s+name\s*=\s*"([^"]+)"([^>]*)>([\s\S]*?)</[^>]*DSML[^>]*parameter\s*>',
    caseSensitive: false,
  );
  static final RegExp _dsmlStringAttr = RegExp(
    r'string\s*=\s*"([^"]*)"',
    caseSensitive: false,
  );
  static final RegExp _dsmlAnyTag = RegExp(
    r'</?[^>]*DSML[^>]*>',
    caseSensitive: false,
  );

  /// Parses the raw string response from an LLM.
  static ParsedModelOutput parse(String rawOutput) {
    // Normalize DeepSeek's native tool-call dialect before scanning for
    // <system_call> blocks. Its calls are merged into the same result.
    final dsml = _extractDsmlCalls(rawOutput);
    rawOutput = dsml.remainingText;

    final List<SystemCall> calls = List<SystemCall>.from(dsml.systemCalls);
    final StringBuffer scratchpad = StringBuffer();
    String? explicitText = dsml.textMessage;
    Map<String, dynamic>? explicitA2UI = dsml.a2uiPayload;

    int cursor = 0;

    while (cursor < rawOutput.length) {
      final startIndex = rawOutput.indexOf(_openTag, cursor);
      if (startIndex == -1) {
        // No more <system_call> tags
        final trailingText = rawOutput.substring(cursor).trim();
        if (trailingText.isNotEmpty) {
          // Recovery: models sometimes emit the delivery object on its own,
          // without the <system_call> tags (for example {"a2ui": [...]}).
          // Recognize only unmistakable delivery shapes, otherwise the object
          // would be rendered to the user as raw JSON text.
          if (calls.isEmpty && explicitText == null && explicitA2UI == null) {
            final bareDelivery = _tryBareDelivery(trailingText);
            if (bareDelivery != null) {
              explicitText = bareDelivery.text;
              explicitA2UI = bareDelivery.a2ui;
            } else if (!trailingText.contains(_openTag)) {
              // Fallback: If no system calls and no delivery commands exist in
              // the entire output, treat the raw text as a direct message so
              // simple text-only LLMs still function.
              // CRITICAL: Ensure raw <system_call> tags never leak into explicit text.
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
          onA2UI: (payload) {
            explicitA2UI = payload;
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

  /// Converts DeepSeek DSML invokes into [SystemCall]s and delivery text.
  ///
  /// The remaining text has every DSML tag removed so malformed or unrelated
  /// fragments can never leak into the chat transcript.
  static _DsmlExtraction _extractDsmlCalls(String rawOutput) {
    final calls = <SystemCall>[];
    String? textMessage;
    Map<String, dynamic>? a2uiPayload;

    void consumeInvoke(Match invoke) {
      final name = (invoke.group(1) ?? '').trim();
      if (name.isEmpty) return;

      final params = <String, dynamic>{};
      for (final parameter in _dsmlParameter.allMatches(
        invoke.group(2) ?? '',
      )) {
        final key = (parameter.group(1) ?? '').trim();
        if (key.isEmpty) continue;

        final rawValue = parameter.group(3) ?? '';
        final stringAttr = _dsmlStringAttr.firstMatch(
          parameter.group(2) ?? '',
        );
        final isString =
            (stringAttr?.group(1) ?? 'true').toLowerCase() != 'false';

        // `string="false"` carries a JSON value. The canonical DeepSeek shape
        // nests the whole parameter object under the `parameters` key.
        if (!isString && key == 'parameters') {
          final decoded = _tryRepairAndDecodeJson(rawValue).decoded;
          if (decoded != null) {
            params.addAll(decoded);
            continue;
          }
        }

        params[key] = isString ? rawValue.trim() : _decodeDsmlValue(rawValue);
      }

      if (name == 'send_ui_message') {
        final message = params['message'];
        if (message is String) {
          textMessage = message;
        } else if (message is Map) {
          final a2ui = message['a2ui'];
          if (a2ui is List && a2ui.isNotEmpty) {
            a2uiPayload = {'messages': a2ui};
          }
        }
        return;
      }

      calls.add(SystemCall(command: name, parameters: params));
    }

    var scrubbed = rawOutput.replaceAllMapped(_dsmlInvoke, (invoke) {
      consumeInvoke(invoke);
      return '\n';
    });

    // Scrub residual or unclosed tag fragments.
    if (_dsmlAnyTag.hasMatch(scrubbed)) {
      scrubbed = scrubbed.replaceAll(_dsmlAnyTag, '').trim();
    }

    return _DsmlExtraction(
      remainingText: scrubbed,
      systemCalls: calls,
      textMessage: textMessage,
      a2uiPayload: a2uiPayload,
    );
  }

  /// Decodes a non-string DSML parameter, falling back to its raw text.
  static dynamic _decodeDsmlValue(String rawValue) {
    final value = rawValue.trim();
    try {
      return json.decode(value);
    } catch (_) {
      return value;
    }
  }

  /// Parses and processes a single `<system_call>` JSON payload.
  static void _processSystemCallBlock(
    String jsonContent, {
    required List<SystemCall> calls,
    required void Function(String) onTextMessage,
    required void Function(Map<String, dynamic>) onA2UI,
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
        if (cmd == 'send_ui_message') {
          final message = params['message'] ?? decoded['message'];
          if (message is String) {
            onTextMessage(message);
            return;
          }
          if (message is Map) {
            final map = Map<String, dynamic>.from(message);
            final a2ui = map['a2ui'];
            if (a2ui is List && a2ui.isNotEmpty) {
              onA2UI({'messages': a2ui});
              return;
            }
          }
          // A malformed delivery shape is not a tool call. Returning without
          // setting text/A2UI makes the engine retry the delivery.
          return;
        }
        calls.add(SystemCall(command: cmd, parameters: params));
        return;
      }
    }

    // 2. Resilient fallback for an unclosed or truncated text delivery.
    final sendMsgMatch = RegExp(
      r'"command"\s*:\s*"send_ui_message"[\s\S]*?"message"\s*:\s*"(.*)',
      dotAll: true,
    ).firstMatch(jsonContent);

    if (sendMsgMatch != null) {
      var text = sendMsgMatch.group(1) ?? '';
      text = text.replaceAll(RegExp(r'"\s*\}*\s*$'), '');
      text = _unescapeJsonString(text);
      onTextMessage(text);
      return;
    }

    // 3. If unrecoverable, record a malformed_json_error with exact line, column, and snippet
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

  /// Recovers a delivery emitted without `<system_call>` tags.
  ///
  /// Accepted shapes, in order:
  /// - `{"command": "send_ui_message", "parameters": {...}}` (full envelope)
  /// - `{"message": "text"}` or `{"message": {"a2ui": [...]}}` (message only)
  /// - `{"a2ui": [...]}` (message list only)
  ///
  /// Returns null for any other JSON value so an ordinary JSON text reply is
  /// still delivered as text. The input may be wrapped in a markdown fence.
  static _BareDelivery? _tryBareDelivery(String text) {
    final cleaned = _stripMarkdownFences(text);
    if (!cleaned.startsWith('{') || !cleaned.endsWith('}')) return null;

    final decoded = _tryRepairAndDecodeJson(cleaned).decoded;
    if (decoded == null) return null;

    if (decoded['command'] == 'send_ui_message') {
      final params = decoded['parameters'];
      final message = params is Map ? params['message'] : decoded['message'];
      return _deliveryFromMessage(message);
    }

    if (decoded.containsKey('message')) {
      final recovered = _deliveryFromMessage(decoded['message']);
      if (recovered != null) return recovered;
    }

    return _deliveryFromMessage(decoded);
  }

  /// Converts a `message` value into a delivery, or null when it is not one.
  ///
  /// A string becomes a text delivery; a map becomes an A2UI delivery only when
  /// it carries a non-empty `a2ui` list. Everything else is not a delivery.
  static _BareDelivery? _deliveryFromMessage(dynamic message) {
    if (message is String) {
      return message.trim().isEmpty ? null : _BareDelivery(text: message);
    }
    if (message is Map) {
      final a2ui = message['a2ui'];
      if (a2ui is List && a2ui.isNotEmpty) {
        return _BareDelivery(a2ui: {'messages': a2ui});
      }
    }
    return null;
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

/// Result of recovering a delivery object emitted without `<system_call>` tags.
class _BareDelivery {
  /// Text delivery recovered from a bare `message` string.
  final String? text;

  /// A2UI delivery recovered from a bare `a2ui` list, shaped as
  /// `{'messages': [...]}` for the engine.
  final Map<String, dynamic>? a2ui;

  const _BareDelivery({this.text, this.a2ui});
}

/// Result of normalizing a DeepSeek native tool-call block.
class _DsmlExtraction {
  final String remainingText;
  final List<SystemCall> systemCalls;
  final String? textMessage;
  final Map<String, dynamic>? a2uiPayload;

  const _DsmlExtraction({
    required this.remainingText,
    this.systemCalls = const [],
    this.textMessage,
    this.a2uiPayload,
  });
}
