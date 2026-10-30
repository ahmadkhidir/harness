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

  /// Content discriminator: either `'text'` (Markdown) or `'a2ui'` (declarative widget).
  final String contentType;

  /// User-facing Markdown content when [contentType] is `'text'`, or optional companion text for `'a2ui'`.
  final String? text;

  /// Surface identifier for the mounted A2UI component when [contentType] is `'a2ui'`.
  final String? a2uiSurfaceId;

  /// Identifier of the model that generated this turn (null for user turns).
  final String? modelUsed;

  /// Total token consumption recorded for this turn.
  final int? tokenCount;

  Turn({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.sender,
    required this.contentType,
    this.text,
    this.a2uiSurfaceId,
    this.modelUsed,
    this.tokenCount,
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
      if (modelUsed != null) 'modelUsed': modelUsed,
      if (tokenCount != null) 'tokenCount': tokenCount,
    };
  }

  /// Deserializes a turn from a JSON map.
  factory Turn.fromJson(Map<String, dynamic> json) {
    return Turn(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sender: json['sender'] as String,
      contentType: json['contentType'] as String,
      text: json['text'] as String?,
      a2uiSurfaceId: json['a2uiSurfaceId'] as String?,
      modelUsed: json['modelUsed'] as String?,
      tokenCount: json['tokenCount'] as int?,
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
    String? modelUsed,
    int? tokenCount,
  }) {
    return Turn(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      sender: sender ?? this.sender,
      contentType: contentType ?? this.contentType,
      text: text ?? this.text,
      a2uiSurfaceId: a2uiSurfaceId ?? this.a2uiSurfaceId,
      modelUsed: modelUsed ?? this.modelUsed,
      tokenCount: tokenCount ?? this.tokenCount,
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
