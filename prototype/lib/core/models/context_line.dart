/// Enumeration of line types supported by the `context.txt` plaintext protocol.
enum ContextLineType {
  /// Consolidated summary line placed at line 1 after background compaction runs.
  summary,

  /// Discrete single line representing a human user prompt.
  user,

  /// Discrete single line representing an agent response or A2UI stub.
  agent,
}

/// Represents a single discrete line within `context.txt`.
///
/// `context.txt` is the line-oriented plain text file maintained inside each `/sessions/<session_id>/`
/// folder. It is designed specifically for fast line-based regex matching (`grep`) and sequential
/// reading (`read_file`) directly on mobile devices without parsing full JSON files.
///
/// #### Rules from docs/Harness/schema.md:
/// 1. Every entry begins with one of three uppercase prefix tags followed by a colon and a space:
///    `SUMMARY: `, `USER: `, or `AGENT: `.
/// 2. If user or agent text contains line breaks, lines are sanitized (newline characters escaped as
///    `\n` or folded) to guarantee that each dialogue event occupies a single discrete line.
/// 3. For turns where `send_a2ui` was dispatched without companion text, the entry is formatted as:
///    `AGENT: [A2UI: surfaceId=<id>, components=<root_component_type>]`.
/// 4. When the session compactor runs, older `USER:` and `AGENT:` lines are deleted and replaced by a
///    consolidated `SUMMARY:` line at line 1.
class ContextLine {
  /// The prefix discriminator tag (`summary`, `user`, or `agent`).
  final ContextLineType type;

  /// The raw unescaped textual content of the dialogue turn or summary.
  final String content;

  ContextLine({
    required this.type,
    required this.content,
  });

  /// Sanitizes text to guarantee it occupies exactly one discrete line in `context.txt`.
  ///
  /// Non-obvious logic:
  /// Carriage returns (`\r`) are stripped, and newlines (`\n`) are converted to the two-character
  /// literal escape sequence `\n`. This ensures regex scanners (`grep`) and line counters treat
  /// each conversational turn as a single atomic line on disk.
  static String sanitizeText(String text) {
    return text.replaceAll('\r', '').replaceAll('\n', r'\n');
  }

  /// Reverses [sanitizeText] by replacing literal `\n` escape sequences back with real newlines.
  static String desanitizeText(String text) {
    return text.replaceAll(r'\n', '\n');
  }

  /// Helper to format companion-less A2UI delivery stubs according to rule 3 of `schema.md`.
  static String formatA2UIStub({
    required String surfaceId,
    required String rootComponentType,
  }) {
    return '[A2UI: surfaceId=$surfaceId, components=$rootComponentType]';
  }

  /// Formats the context line into a single newline-terminated string ready to append to `context.txt`.
  String format() {
    final sanitized = sanitizeText(content);
    switch (type) {
      case ContextLineType.summary:
        return 'SUMMARY: $sanitized\n';
      case ContextLineType.user:
        return 'USER: $sanitized\n';
      case ContextLineType.agent:
        return 'AGENT: $sanitized\n';
    }
  }

  /// Parses a discrete line read from `context.txt` into a [ContextLine] instance.
  ///
  /// Throws a [FormatException] if the line does not begin with an authorized prefix tag.
  static ContextLine parse(String line) {
    // Strip trailing newline character if present
    final trimmed = line.endsWith('\n') ? line.substring(0, line.length - 1) : line;

    if (trimmed.startsWith('SUMMARY: ')) {
      return ContextLine(
        type: ContextLineType.summary,
        content: desanitizeText(trimmed.substring(9)),
      );
    } else if (trimmed.startsWith('USER: ')) {
      return ContextLine(
        type: ContextLineType.user,
        content: desanitizeText(trimmed.substring(6)),
      );
    } else if (trimmed.startsWith('AGENT: ')) {
      return ContextLine(
        type: ContextLineType.agent,
        content: desanitizeText(trimmed.substring(7)),
      );
    } else {
      throw FormatException(
        'Invalid context.txt line format. Must start with "SUMMARY: ", "USER: ", or "AGENT: ": "$line"',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextLine &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          content == other.content;

  @override
  int get hashCode => type.hashCode ^ content.hashCode;
}
