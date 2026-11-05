/// Lifecycle state of a scheduled self-prompt timer.
enum ScheduledTimerStatus {
  /// Waiting for `firesAt`.
  scheduled,

  /// The time elapsed but the session was inactive or a turn was running.
  queued,

  /// The self-prompt turn is currently executing.
  running,

  /// The timer fired and its turn was dispatched.
  completed,

  /// The timer was cancelled before firing.
  cancelled,
}

/// A prompt the model scheduled to send itself after a delay.
///
/// Stored under the session's `timers` array in `turns.json`. A fired timer
/// never creates a chat turn; it appends a `USER:` line to `context.txt` and
/// runs the normal agent loop.
class ScheduledTimer {
  /// Unique timer identifier (`timer_...`).
  final String id;

  /// Session that owns the timer.
  final String sessionId;

  /// Prompt delivered back to the model when the timer fires.
  final String prompt;

  /// Optional user-facing label (for example "Workout check-in").
  final String? label;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Absolute firing time (UTC).
  final DateTime firesAt;

  /// Current lifecycle state.
  final ScheduledTimerStatus status;

  /// When the timer fired. Omitted unless the timer completed.
  final DateTime? firedAt;

  /// When the timer was cancelled. Omitted unless cancelled.
  final DateTime? cancelledAt;

  const ScheduledTimer({
    required this.id,
    required this.sessionId,
    required this.prompt,
    this.label,
    required this.createdAt,
    required this.firesAt,
    this.status = ScheduledTimerStatus.scheduled,
    this.firedAt,
    this.cancelledAt,
  });

  /// True when the timer is still waiting for its firing time.
  bool get isPending =>
      status == ScheduledTimerStatus.scheduled ||
      status == ScheduledTimerStatus.queued ||
      status == ScheduledTimerStatus.running;

  /// Serializes the timer, omitting unused timestamp fields.
  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'prompt': prompt,
        if (label != null && label!.isNotEmpty) 'label': label,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'firesAt': firesAt.toUtc().toIso8601String(),
        'status': status.name,
        if (firedAt != null) 'firedAt': firedAt!.toUtc().toIso8601String(),
        if (cancelledAt != null)
          'cancelledAt': cancelledAt!.toUtc().toIso8601String(),
      };

  /// Deserializes a timer from a JSON map.
  factory ScheduledTimer.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? 'scheduled';
    final status = ScheduledTimerStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => ScheduledTimerStatus.scheduled,
    );

    return ScheduledTimer(
      id: json['id']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      label: json['label']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      firesAt: DateTime.tryParse(json['firesAt']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      status: status,
      firedAt: DateTime.tryParse(json['firedAt']?.toString() ?? '')?.toUtc(),
      cancelledAt:
          DateTime.tryParse(json['cancelledAt']?.toString() ?? '')?.toUtc(),
    );
  }

  /// Returns a copy with selected fields replaced.
  ScheduledTimer copyWith({
    String? prompt,
    String? label,
    DateTime? firesAt,
    ScheduledTimerStatus? status,
    DateTime? firedAt,
    DateTime? cancelledAt,
  }) {
    return ScheduledTimer(
      id: id,
      sessionId: sessionId,
      prompt: prompt ?? this.prompt,
      label: label ?? this.label,
      createdAt: createdAt,
      firesAt: firesAt ?? this.firesAt,
      status: status ?? this.status,
      firedAt: firedAt ?? this.firedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledTimer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
