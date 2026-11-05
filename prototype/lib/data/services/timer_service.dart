import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/models/scheduled_timer.dart';
import 'notification_tap_router.dart';
import 'session_service.dart';

/// Persists and executes model-scheduled self-prompt timers (FEAT-010).
///
/// Timers live in the session's `turns.json` envelope. While the app is alive,
/// a Dart timer triggers the self-prompt; a local notification is scheduled at
/// the same instant so the user knows to return when the app is not running.
/// Overdue timers are reconciled on launch/resume and queued until their
/// session is active and idle.
class TimerService {
  /// Active service instance for UI access.
  static TimerService? instance;

  /// Session persistence.
  final SessionService sessionService;

  /// Injectable notification plugin (nullable for tests).
  final FlutterLocalNotificationsPlugin? notifications;

  /// Timer ID -> in-process timer.
  final Map<String, Timer> _activeTimers = {};

  /// Session ID -> timers, used for stream emissions.
  final Map<String, List<ScheduledTimer>> _cache = {};

  final StreamController<List<ScheduledTimer>> _changes =
      StreamController<List<ScheduledTimer>>.broadcast();

  /// Invoked when a timer becomes due (queued for execution).
  void Function(ScheduledTimer timer)? onDue;

  /// Invoked when a timer notification is tapped.
  void Function(String sessionId)? onNotificationTap;

  bool _notificationsReady = false;
  Future<void>? _notificationInitialization;
  int _sequence = 0;

  /// Creates a service around the session store.
  TimerService({
    required this.sessionService,
    this.notifications,
  }) {
    instance = this;
  }

  /// Current timers across loaded sessions.
  List<ScheduledTimer> get allTimers =>
      _cache.values.expand((timers) => timers).toList();

  /// Watches pending timers for [sessionId].
  Stream<List<ScheduledTimer>> watch(String sessionId) async* {
    yield _pendingFor(sessionId, await sessionService.loadTimers(sessionId));
    await for (final _ in _changes.stream) {
      yield _pendingFor(sessionId, _cache[sessionId] ?? const []);
    }
  }

  List<ScheduledTimer> _pendingFor(
    String sessionId,
    List<ScheduledTimer> timers,
  ) {
    return timers
        .where((timer) => timer.isPending)
        .toList()
      ..sort((a, b) => a.firesAt.compareTo(b.firesAt));
  }

  /// Schedules a timer for [sessionId].
  Future<ScheduledTimer> schedule({
    required String sessionId,
    required String prompt,
    required Duration delay,
    String? label,
  }) async {
    final now = DateTime.now().toUtc();
    final timer = ScheduledTimer(
      id: 'timer_${now.millisecondsSinceEpoch}_${_sequence++}',
      sessionId: sessionId,
      prompt: prompt,
      label: label,
      createdAt: now,
      firesAt: now.add(delay),
    );

    await sessionService.upsertTimer(sessionId, timer);
    await _refresh(sessionId);
    await _arm(timer);
    return timer;
  }

  /// Cancels a timer by ID.
  Future<bool> cancel(String sessionId, String timerId) async {
    final timers = await sessionService.loadTimers(sessionId);
    final index = timers.indexWhere((timer) => timer.id == timerId);
    if (index == -1) return false;

    final timer = timers[index];
    if (!timer.isPending) return false;

    await _cancelNotification(timer);
    _activeTimers.remove(timerId)?.cancel();

    final cancelled = timer.copyWith(
      status: ScheduledTimerStatus.cancelled,
      cancelledAt: DateTime.now().toUtc(),
    );
    await sessionService.upsertTimer(sessionId, cancelled);
    await _refresh(sessionId);
    return true;
  }

  /// Lists pending timers for a session.
  Future<List<ScheduledTimer>> list(String sessionId) async {
    final timers = await sessionService.loadTimers(sessionId);
    _cache[sessionId] = timers;
    return _pendingFor(sessionId, timers);
  }

  /// Marks a timer as running.
  Future<void> markRunning(ScheduledTimer timer) async {
    await sessionService.upsertTimer(
      timer.sessionId,
      timer.copyWith(status: ScheduledTimerStatus.running),
    );
    await _refresh(timer.sessionId);
  }

  /// Marks a timer as completed.
  Future<void> markCompleted(ScheduledTimer timer) async {
    await sessionService.upsertTimer(
      timer.sessionId,
      timer.copyWith(
        status: ScheduledTimerStatus.completed,
        firedAt: DateTime.now().toUtc(),
      ),
    );
    await _refresh(timer.sessionId);
  }

  /// Returns queued timers for [sessionId] in firing order.
  Future<List<ScheduledTimer>> queued(String sessionId) async {
    final timers = await sessionService.loadTimers(sessionId);
    return timers
        .where((timer) => timer.status == ScheduledTimerStatus.queued)
        .toList()
      ..sort((a, b) => a.firesAt.compareTo(b.firesAt));
  }

  /// Restores timers for every session after launch.
  Future<void> restoreAll() async {
    final sessions = await sessionService.getAllSessions();
    final due = <ScheduledTimer>[];

    for (final session in sessions) {
      final timers = await sessionService.loadTimers(session.id);
      final kept = <ScheduledTimer>[];
      var changed = false;

      for (final timer in timers) {
        // Prune completed/cancelled records after 24 hours.
        if (timer.status == ScheduledTimerStatus.completed ||
            timer.status == ScheduledTimerStatus.cancelled) {
          final stamp = timer.firedAt ?? timer.cancelledAt ?? timer.firesAt;
          if (DateTime.now().toUtc().difference(stamp) <
              const Duration(hours: 24)) {
            kept.add(timer);
          } else {
            changed = true;
          }
          continue;
        }

        if (timer.firesAt.isAfter(DateTime.now().toUtc())) {
          kept.add(timer);
          await _arm(timer);
          continue;
        }

        final queued = timer.copyWith(status: ScheduledTimerStatus.queued);
        kept.add(queued);
        due.add(queued);
        changed = changed || timer.status != ScheduledTimerStatus.queued;
        await _cancelNotification(timer);
      }

      if (changed) {
        await sessionService.saveTimers(session.id, kept);
      }
      _cache[session.id] = kept;
    }

    _emit();
    for (final timer in due) {
      onDue?.call(timer);
    }
  }

  /// Initializes notification handling and attaches callbacks.
  Future<void> start({
    void Function(ScheduledTimer timer)? onDue,
    void Function(String sessionId)? onNotificationTap,
  }) async {
    this.onDue = onDue;
    this.onNotificationTap = onNotificationTap;
    await _ensureNotifications();
  }

  Future<void> _arm(ScheduledTimer timer) async {
    _activeTimers.remove(timer.id)?.cancel();

    final remaining = timer.firesAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      await _queueDue(timer);
      return;
    }

    _activeTimers[timer.id] = Timer(remaining, () => _queueDue(timer));
    await _scheduleNotification(timer);
  }

  Future<void> _queueDue(ScheduledTimer timer) async {
    _activeTimers.remove(timer.id)?.cancel();

    final current = (await sessionService.loadTimers(timer.sessionId))
        .where((item) => item.id == timer.id)
        .firstOrNull;
    if (current == null || !current.isPending) return;
    if (current.status == ScheduledTimerStatus.queued) {
      onDue?.call(current);
      return;
    }

    final queued = current.copyWith(status: ScheduledTimerStatus.queued);
    await sessionService.upsertTimer(timer.sessionId, queued);
    await _cancelNotification(queued);
    await _refresh(timer.sessionId);
    onDue?.call(queued);
  }

  Future<void> _refresh(String sessionId) async {
    _cache[sessionId] = await sessionService.loadTimers(sessionId);
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(allTimers);
    }
  }

  Future<void> _ensureNotifications() {
    if (_notificationsReady) return Future.value();
    return _notificationInitialization ??= _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    final plugin = notifications ?? FlutterLocalNotificationsPlugin();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    try {
      await plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            final decoded = json.decode(payload);
            if (decoded is Map && decoded['sessionId'] != null) {
              onNotificationTap?.call(decoded['sessionId'].toString());
            }
          } catch (_) {}
          NotificationTapRouter.route(payload);
        },
      );
      _notificationsReady = true;
    } catch (_) {
      // Headless tests and unsupported hosts keep in-app timers working.
    }
  }

  int _notificationId(String timerId) =>
      1000000 + (timerId.hashCode.abs() % 1000000);

  Future<void> _scheduleNotification(ScheduledTimer timer) async {
    await _ensureNotifications();
    final plugin = notifications ?? FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.requestNotificationsPermission();
        await android?.requestExactAlarmsPermission();
      } catch (_) {}
    } else if (Platform.isIOS) {
      final ios = plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      try {
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (_) {}
    }

    try {
      await plugin.zonedSchedule(
        id: _notificationId(timer.id),
        title: 'Scheduled timer',
        body: timer.label ?? timer.prompt,
        scheduledDate: tz.TZDateTime.from(timer.firesAt, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'harness_timers',
            'Harness Timers',
            channelDescription: 'Timers scheduled by the Harness agent.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: json.encode({
          'type': 'timer',
          'sessionId': timer.sessionId,
          'timerId': timer.id,
        }),
      );
    } catch (_) {
      // The in-app timer still fires even if OS scheduling is unavailable.
    }
  }

  Future<void> _cancelNotification(ScheduledTimer timer) async {
    try {
      final plugin = notifications ?? FlutterLocalNotificationsPlugin();
      await plugin.cancel(id: _notificationId(timer.id));
    } catch (_) {}
  }

  /// Cancels in-process timers and closes streams.
  Future<void> dispose() async {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    await _changes.close();
    if (identical(instance, this)) instance = null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
