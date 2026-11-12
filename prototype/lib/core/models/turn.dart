import 'tool_execution_record.dart';

/// Represents an individual interaction event recorded in a session's `turns.json` audit log.
///
/// Serves as the authoritative source of truth for the Flutter chat UI.
/// Conforms to JSON Schema `https://harness.agent/schemas/turn.schema.json`.
class Turn {
  /// Monotonically increasing or unique turn identifier within the session, e.g. `turn_001`.
  final String id;

  /// Foreign key referencing the parent [Session.id].
  final String sessionId;

  /// Timestamp when the turn was dispatched (UTC).
  final DateTime timestamp;

  /// Originator of the turn message: either `'user'` or `'agent'`.
  final String sender;

  /// Content discriminator: `'text'` (Markdown) or `'a2ui'` (declarative
  /// widget).
  final String contentType;

  /// User-facing Markdown content when [contentType] is `'text'`, or
  /// audit-only text for `'a2ui'` (never rendered as a companion bubble).
  final String? text;

  /// Surface identifier for the mounted A2UI component when [contentType] is `'a2ui'`.
  final String? a2uiSurfaceId;

  /// Raw A2UI message stream delivered through `send_ui_message`.
  final Map<String, dynamic>? a2uiPayload;

  /// Identifier of the model that generated this turn (null for user turns).
  final String? modelUsed;

  /// Total token consumption recorded for this turn.
  final int? tokenCount;

  /// Structured records of tools executed during this turn.
  final List<ToolExecutionRecord> toolCalls;

  Turn({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.sender,
    required this.contentType,
    this.text,
    this.a2uiSurfaceId,
    this.a2uiPayload,
    this.modelUsed,
    this.tokenCount,
    this.toolCalls = const [],
  }) {
    // Schema enum validations
    if (sender != 'user' && sender != 'agent') {
      throw ArgumentError('sender must be "user" or "agent", got "$sender".');
    }
    if (contentType != 'text' && contentType != 'a2ui') {
      throw ArgumentError(
          'contentType must be "text" or "a2ui", got "$contentType".');
    }
    if (tokenCount != null && tokenCount! < 0) {
      throw ArgumentError('tokenCount must be non-negative.');
    }
  }

  /// Convenience getter indicating if the turn originated from the human user.
  bool get isUser => sender == 'user';

  /// Convenience getter indicating if the turn originated from the agent.
  bool get isAgent => sender == 'agent';

  /// Convenience getter indicating if the turn renders an interactive A2UI surface.
  bool get isA2UI => contentType == 'a2ui';

  /// Convenience getter indicating if the turn renders plain Markdown text.
  bool get isText => contentType == 'text';

  /// Serializes the turn into a JSON map adhering to turn.schema.json.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'sender': sender,
      'contentType': contentType,
      if (text != null) 'text': text,
      if (a2uiSurfaceId != null) 'a2uiSurfaceId': a2uiSurfaceId,
      if (a2uiPayload != null) 'a2uiPayload': a2uiPayload,
      if (modelUsed != null) 'modelUsed': modelUsed,
      if (tokenCount != null) 'tokenCount': tokenCount,
      if (toolCalls.isNotEmpty)
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    };
  }

  /// Deserializes a turn from a JSON map.
  factory Turn.fromJson(Map<String, dynamic> json) {
    final rawContentType = json['contentType'] as String? ?? 'text';
    return Turn(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sender: json['sender'] as String,
      // Older sessions may contain action receipts. They are read as ordinary
      // text turns; new action receipts are no longer created.
      contentType: rawContentType == 'action' ? 'text' : rawContentType,
      text: json['text'] as String?,
      a2uiSurfaceId: json['a2uiSurfaceId'] as String?,
      a2uiPayload: json['a2uiPayload'] != null
          ? Map<String, dynamic>.from(json['a2uiPayload'] as Map)
          : null,
      modelUsed: json['modelUsed'] as String?,
      tokenCount: json['tokenCount'] as int?,
      toolCalls: json['toolCalls'] != null
          ? (json['toolCalls'] as List)
              .map((item) => ToolExecutionRecord.fromJson(
                  Map<String, dynamic>.from(item as Map)))
              .toList()
          : const [],
    );
  }

  /// Creates a copy of this turn with the specified fields replaced.
  Turn copyWith({
    String? id,
    String? sessionId,
    DateTime? timestamp,
    String? sender,
    String? contentType,
    String? text,
    String? a2uiSurfaceId,
    Map<String, dynamic>? a2uiPayload,
    String? modelUsed,
    int? tokenCount,
    List<ToolExecutionRecord>? toolCalls,
  }) {
    return Turn(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      sender: sender ?? this.sender,
      contentType: contentType ?? this.contentType,
      text: text ?? this.text,
      a2uiSurfaceId: a2uiSurfaceId ?? this.a2uiSurfaceId,
      a2uiPayload: a2uiPayload ?? this.a2uiPayload,
      modelUsed: modelUsed ?? this.modelUsed,
      tokenCount: tokenCount ?? this.tokenCount,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Turn &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sessionId == other.sessionId &&
          sender == other.sender &&
          contentType == other.contentType &&
          text == other.text &&
          a2uiSurfaceId == other.a2uiSurfaceId;

  @override
  int get hashCode =>
      id.hashCode ^
      sessionId.hashCode ^
      sender.hashCode ^
      contentType.hashCode ^
      (text?.hashCode ?? 0) ^
      (a2uiSurfaceId?.hashCode ?? 0);
}
