import 'package:harness/modules/platform_actions/platform_action_gateway.dart';

/// In-memory [PlatformActionGateway] that records invocations for assertions.
///
/// Tests can toggle permission and availability failures to exercise the
/// module's error-translation contract without invoking native channels.
class FakePlatformActionGateway implements PlatformActionGateway {
  /// Recorded `setAlarm` invocations.
  final List<Map<String, String>> alarms = [];

  /// Recorded `scheduleNotification` invocations.
  final List<Map<String, dynamic>> notifications = [];

  /// Recorded `openUrl` invocations.
  final List<String> openedUrls = [];

  /// Recorded `copyToClipboard` invocations.
  final List<String> copiedTexts = [];

  /// When true, `setAlarm` throws a permission denial for alarms.
  bool denyAlarmPermission = false;

  /// When true, `scheduleNotification` throws a permission denial.
  bool denyNotificationPermission = false;

  /// When true, `setAlarm` reports that alarms are unsupported.
  bool alarmsUnsupported = false;

  /// Result returned by [openUrl].
  bool openUrlResult = true;

  @override
  Future<void> setAlarm({required String time, required String label}) async {
    if (alarmsUnsupported) {
      throw const PlatformActionUnsupportedException(
        'alarms are only supported on Android and iOS.',
      );
    }
    if (denyAlarmPermission) {
      throw const PlatformPermissionException('alarms');
    }
    alarms.add({'time': time, 'label': label});
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    String? body,
    Duration delay = Duration.zero,
  }) async {
    if (denyNotificationPermission) {
      throw const PlatformPermissionException('notifications');
    }
    notifications.add({
      'id': id,
      'title': title,
      'body': body,
      'delayMs': delay.inMilliseconds,
    });
  }

  @override
  Future<bool> openUrl(String url) async {
    openedUrls.add(url);
    return openUrlResult;
  }

  @override
  Future<void> copyToClipboard(String text) async {
    copiedTexts.add(text);
  }
}
