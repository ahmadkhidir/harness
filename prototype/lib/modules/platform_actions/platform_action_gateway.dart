/// Exception thrown when the operating system denies a permission required
/// to complete a platform action.
///
/// The [permission] label is surfaced verbatim in the agent-facing observation
/// so the model can prompt the user to enable the corresponding capability in
/// the device settings.
class PlatformPermissionException implements Exception {
  /// Human-readable name of the denied capability (e.g. `alarms`, `notifications`).
  final String permission;

  /// Optional underlying platform error message.
  final String? details;

  const PlatformPermissionException(this.permission, {this.details});

  @override
  String toString() => 'PlatformPermissionException($permission)';
}

/// Exception thrown when a platform capability is not available on the current
/// device or operating system (for example a desktop build attempting to
/// schedule a mobile alarm).
class PlatformActionUnsupportedException implements Exception {
  /// Description of the unsupported capability.
  final String message;

  const PlatformActionUnsupportedException(this.message);

  @override
  String toString() => 'PlatformActionUnsupportedException: $message';
}

/// Exception thrown when a platform plugin reports a non-permission failure.
class PlatformActionFailureException implements Exception {
  /// Description of the underlying failure.
  final String message;

  const PlatformActionFailureException(this.message);

  @override
  String toString() => 'PlatformActionFailureException: $message';
}

/// Contract for the native capabilities bridged by the Platform Actions module.
///
/// Implementations are intentionally thin adapters around operating-system
/// APIs. [PlatformActionsModule] owns validation and error translation, while
/// gateways focus exclusively on invoking the device capability:
///
/// - `setAlarm` schedules a wake-up alarm through the system alarm manager.
/// - `scheduleNotification` posts or schedules a local notification.
/// - `openUrl` launches a web link or registered deep link.
/// - `copyToClipboard` writes the supplied text to the system clipboard.
///
/// Tests inject an in-memory fake implementing this interface so acceptance
/// criteria can be verified without invoking real OS channels.
abstract class PlatformActionGateway {
  /// Schedules an alarm for the next occurrence of [time] (24-hour `HH:mm`)
  /// and labels it with [label].
  ///
  /// Throws [PlatformPermissionException] when alarm or notification
  /// permissions are denied, or [PlatformActionUnsupportedException] when the
  /// current platform cannot schedule alarms.
  Future<void> setAlarm({required String time, required String label});

  /// Schedules a local notification identified by [id].
  ///
  /// When [delay] is zero the notification is presented immediately. Throws
  /// [PlatformPermissionException] when notification permission is denied.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    String? body,
    Duration delay = Duration.zero,
  });

  /// Launches [url] externally.
  ///
  /// Returns `true` when the operating system accepted the URL, or `false`
  /// when no handler is available for the scheme.
  Future<bool> openUrl(String url);

  /// Copies [text] to the system clipboard.
  Future<void> copyToClipboard(String text);
}
