/// Represents an isolated conversation thread workspace within Harness.
///
/// Each session maps to an on-device directory under `<AppDocuments>/Harness/sessions/<id>/`
/// containing `turns.json` (authoritative UI log) and `context.txt` (line-oriented transcript).
/// Conforms to JSON Schema `https://harness.agent/schemas/session.schema.json`.
class Session {
  /// Unique stable identifier for the session, e.g. `sess_1730235400`.
  final String id;

  /// User-facing descriptive title for the session (max 128 characters).
  final String title;

  /// Timestamp when the session was created (UTC).
  final DateTime createdAt;

  /// Timestamp when the session was last active (UTC).
  final DateTime updatedAt;

  /// Count of completed dialogue turns recorded in `turns.json`.
  final int totalTurns;

  /// Current byte size of `context.txt` on disk.
  final int contextSizeBytes;

  /// Number of times `context.txt` has undergone background compaction.
  final int compactionCount;

  /// Timestamp of the most recent compaction run, or null if never compacted.
  final DateTime? lastCompactedAt;

  Session({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.totalTurns = 0,
    this.contextSizeBytes = 0,
    this.compactionCount = 0,
    this.lastCompactedAt,
  }) {
    // Validate schema constraints specified in docs/Harness/schema.md
    if (title.length > 128) {
      throw ArgumentError('Session title cannot exceed 128 characters.');
    }
    if (totalTurns < 0) {
      throw ArgumentError('totalTurns must be non-negative.');
    }
    if (contextSizeBytes < 0) {
      throw ArgumentError('contextSizeBytes must be non-negative.');
    }
    if (compactionCount < 0) {
      throw ArgumentError('compactionCount must be non-negative.');
    }
  }

  /// Converts the session instance into a JSON-encodable map conforming to schema.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'totalTurns': totalTurns,
      'contextSizeBytes': contextSizeBytes,
      'compactionCount': compactionCount,
      'lastCompactedAt': lastCompactedAt?.toUtc().toIso8601String(),
    };
  }

  /// Deserializes a session instance from a JSON map.
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      totalTurns: json['totalTurns'] as int? ?? 0,
      contextSizeBytes: json['contextSizeBytes'] as int? ?? 0,
      compactionCount: json['compactionCount'] as int? ?? 0,
      lastCompactedAt: json['lastCompactedAt'] != null
          ? DateTime.parse(json['lastCompactedAt'] as String)
          : null,
    );
  }

  /// Creates a copy of this session with the given fields replaced.
  Session copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalTurns,
    int? contextSizeBytes,
    int? compactionCount,
    DateTime? lastCompactedAt,
  }) {
    return Session(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalTurns: totalTurns ?? this.totalTurns,
      contextSizeBytes: contextSizeBytes ?? this.contextSizeBytes,
      compactionCount: compactionCount ?? this.compactionCount,
      lastCompactedAt: lastCompactedAt ?? this.lastCompactedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          totalTurns == other.totalTurns &&
          contextSizeBytes == other.contextSizeBytes &&
          compactionCount == other.compactionCount;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      totalTurns.hashCode ^
      contextSizeBytes.hashCode ^
      compactionCount.hashCode;
}
