/// Shared routing for local-notification taps.
///
/// Both platform action notifications and scheduled timers initialize the same
/// plugin; keeping the callback here prevents one initializer from clearing the
/// other's tap handling.
class NotificationTapRouter {
  /// Invoked with the raw notification payload.
  static void Function(String? payload)? onTap;

  /// Routes a notification response payload.
  static void route(String? payload) {
    onTap?.call(payload);
  }
}
