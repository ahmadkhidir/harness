import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/notification_tap_router.dart';
import 'platform_action_gateway.dart';

/// Production [PlatformActionGateway] backed by operating-system capabilities.
///
/// The gateway deliberately keeps all plugin initialization lazy: constructing
/// it is side-effect free, which lets unit tests build [PlatformActionsModule]
/// instances on desktop and CI hosts without touching native channels.
///
/// Alarm scheduling uses `AndroidScheduleMode.alarmClock`, which delegates to
/// Android's `AlarmManager.setAlarmClock()` through `flutter_local_notifications`
/// and therefore receives the same wake-up and exact-timing guarantees as the
/// device clock application. On iOS the closest available capability is a
/// scheduled local notification, because iOS does not expose a public API for
/// creating entries in the Clock app's alarm list.
class NativePlatformActionGateway implements PlatformActionGateway {
  /// Notification plugin instance used for alarms and scheduled reminders.
  final FlutterLocalNotificationsPlugin _notifications;

  /// Tracks whether [FlutterLocalNotificationsPlugin.initialize] has run.
  bool _initialized = false;

  /// Monotonically increasing identifier used when the caller omits one.
  int _nextNotificationId = 1000;

  /// Creates a gateway around [notifications], allowing tests to substitute a
  /// configured plugin instance when needed.
  NativePlatformActionGateway({FlutterLocalNotificationsPlugin? notifications})
      : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> setAlarm({required String time, required String label}) async {
    _assertMobilePlatform('alarms');
    await _ensureInitialized();
    await _requestPermission('alarms');

    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    // Compute the next local wall-clock occurrence. A time already in the past
    // rolls forward to tomorrow, matching the behaviour of the system clock app.
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: _allocateId(),
      title: 'Alarm: $label',
      body: 'Your scheduled alarm is ringing.',
      scheduledDate: tz.TZDateTime.from(scheduled, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'harness_alarms',
          'Harness Alarms',
          channelDescription: 'Alarms scheduled by the Harness agent.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: 'harness:alarm',
    );
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    String? body,
    Duration delay = Duration.zero,
  }) async {
    _assertMobilePlatform('notifications');
    await _ensureInitialized();
    await _requestPermission('notifications');

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'harness_reminders',
        'Harness Reminders',
        channelDescription: 'Reminders scheduled by the Harness agent.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    if (delay <= Duration.zero) {
      await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: 'harness:notification',
      );
      return;
    }

    // Delay-based scheduling is resolved against an absolute instant, so no
    // local timezone database lookup is required for correctness.
    final scheduled = tz.TZDateTime.from(
      DateTime.now().add(delay),
      tz.UTC,
    );
    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'harness:notification',
    );
  }

  @override
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Lazily initializes the local-notification plugin with the Android
  /// launcher icon and default Darwin presentation options.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        NotificationTapRouter.route(response.payload);
      },
    );
    _initialized = true;
  }

  /// Requests the capabilities required for [capability].
  ///
  /// Android 13+ requires an explicit runtime notification permission, while
  /// Android 14+ additionally gates exact alarms behind a user-granted special
  /// access permission. iOS requests alert, badge, and sound permissions.
  Future<void> _requestPermission(String capability) async {
    if (Platform.isAndroid) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;

      final notificationsGranted =
          await android.requestNotificationsPermission() ?? true;
      if (!notificationsGranted) {
        throw PlatformPermissionException(capability);
      }
      if (capability == 'alarms') {
        final exactGranted =
            await android.requestExactAlarmsPermission() ?? true;
        if (!exactGranted) {
          throw PlatformPermissionException(capability);
        }
      }
    } else if (Platform.isIOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
      if (!granted) {
        throw PlatformPermissionException(capability);
      }
    }
  }

  /// Guards alarm and notification capabilities on platforms without them.
  void _assertMobilePlatform(String capability) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw PlatformActionUnsupportedException(
        '$capability are only supported on Android and iOS.',
      );
    }
  }

  /// Allocates a unique notification identifier.
  int _allocateId() {
    final id = _nextNotificationId;
    _nextNotificationId++;
    return id;
  }
}
