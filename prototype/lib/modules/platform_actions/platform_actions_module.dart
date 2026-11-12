import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../base/harness_module.dart';
import 'native_platform_action_gateway.dart';
import 'platform_action_gateway.dart';

/// Bridges agent system calls to native mobile operating-system capabilities.
///
/// Implements FEAT-007:
/// - Exposes `set_alarm`, `schedule_notification`, `open_url`, and
///   `copy_to_clipboard` as registered harness commands.
/// - Validates every payload before touching native channels, so malformed
///   times, URLs, or clipboard payloads are rejected as model-readable errors.
/// - Translates denied OS permissions into the observation contract described
///   by the feature specification (for example `Permission denied for alarms`).
class PlatformActionsModule extends HarnessModule {
  /// Native capability adapter.
  final PlatformActionGateway gateway;

  /// Creates a module backed by [gateway].
  ///
  /// When omitted, the production [NativePlatformActionGateway] is used. Tests
  /// should inject an in-memory fake to avoid invoking native channels.
  PlatformActionsModule({PlatformActionGateway? gateway})
      : gateway = gateway ?? NativePlatformActionGateway();

  @override
  String get moduleName => 'platform_actions';

  /// 24-hour wall-clock time accepted by `set_alarm` (for example `07:00` or
  /// `7:05`). Anchored with `^`/`\$` so trailing garbage is rejected.
  static final RegExp _timePattern = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');

  /// RFC 3986 scheme grammar used to reject relative paths passed to `open_url`.
  static final RegExp _uriSchemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*$');

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'set_alarm',
          description:
              'Schedules a native device alarm for the next occurrence of a 24-hour time. Requires a time in HH:mm format and a descriptive label.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'time': {
                'type': 'string',
                'description':
                    'Wall-clock time in 24-hour HH:mm format, e.g. "07:00".',
              },
              'label': {
                'type': 'string',
                'minLength': 1,
                'maxLength': 128,
                'description': 'Short label displayed with the alarm.',
              },
            },
            'required': ['time', 'label'],
          },
        ),
        CommandDefinition(
          command: 'schedule_notification',
          description:
              'Schedules a local device notification, either immediately or after a delay in seconds.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'minLength': 1,
                'maxLength': 128,
                'description': 'Notification title.',
              },
              'body': {
                'type': 'string',
                'maxLength': 512,
                'description': 'Optional notification body text.',
              },
              'delaySeconds': {
                'type': 'integer',
                'minimum': 0,
                'description':
                    'Seconds to wait before presenting the notification. Zero posts immediately.',
              },
              'id': {
                'type': 'integer',
                'description':
                    'Optional stable notification identifier used to replace an existing notification.',
              },
            },
            'required': ['title'],
          },
        ),
        CommandDefinition(
          command: 'open_url',
          description:
              'Opens a web link or registered deep link using the platform URL handler.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'minLength': 1,
                'description':
                    'Absolute URI with a scheme, e.g. "https://example.com" or "mailto:user@example.com".',
              },
            },
            'required': ['url'],
          },
        ),
        CommandDefinition(
          command: 'copy_to_clipboard',
          description: 'Copies the supplied text to the device clipboard.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'minLength': 1,
                'description': 'Text content to place on the clipboard.',
              },
            },
            'required': ['text'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    switch (command) {
      case 'set_alarm':
        return _handleSetAlarm(parameters);
      case 'schedule_notification':
        return _handleScheduleNotification(parameters);
      case 'open_url':
        return _handleOpenUrl(parameters);
      case 'copy_to_clipboard':
        return _handleCopyToClipboard(parameters);
      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unrecognized platform action: "$command".',
        );
    }
  }

  /// Validates and schedules an alarm without invoking native channels when the
  /// request is malformed.
  Future<SystemResponse> _handleSetAlarm(Map<String, dynamic> parameters) async {
    final time = parameters['time'];
    final label = parameters['label'];

    if (time is! String || time.trim().isEmpty) {
      return _validationError(
        'set_alarm',
        'Missing or invalid "time". Provide a 24-hour HH:mm value such as "07:00".',
      );
    }
    final cleanTime = time.trim();
    if (!_timePattern.hasMatch(cleanTime)) {
      return _validationError(
        'set_alarm',
        'Invalid time format "$cleanTime" for set_alarm. Expected 24-hour HH:mm, e.g. "07:00".',
      );
    }

    if (label is! String || label.trim().isEmpty) {
      return _validationError(
        'set_alarm',
        'Missing or invalid "label". Provide a short descriptive alarm label.',
      );
    }
    final cleanLabel = label.trim();
    if (cleanLabel.length > 128) {
      return _validationError(
        'set_alarm',
        'Alarm label must be 128 characters or fewer.',
      );
    }

    return _runNative(
      command: 'set_alarm',
      operation: () => gateway.setAlarm(
        time: cleanTime,
        label: cleanLabel,
      ),
    );
  }

  /// Validates and schedules a local notification.
  Future<SystemResponse> _handleScheduleNotification(
    Map<String, dynamic> parameters,
  ) async {
    final title = parameters['title'];
    if (title is! String || title.trim().isEmpty) {
      return _validationError(
        'schedule_notification',
        'Missing or invalid "title". Provide a non-empty notification title.',
      );
    }
    final cleanTitle = title.trim();
    if (cleanTitle.length > 128) {
      return _validationError(
        'schedule_notification',
        'Notification title must be 128 characters or fewer.',
      );
    }

    final body = parameters['body'];
    if (body != null && body is! String) {
      return _validationError(
        'schedule_notification',
        'Invalid "body": expected a string.',
      );
    }
    if (body is String && body.length > 512) {
      return _validationError(
        'schedule_notification',
        'Notification body must be 512 characters or fewer.',
      );
    }

    final delaySeconds = parameters['delaySeconds'];
    if (delaySeconds != null && (delaySeconds is! int || delaySeconds < 0)) {
      return _validationError(
        'schedule_notification',
        'Invalid "delaySeconds": expected a non-negative integer.',
      );
    }

    final id = parameters['id'];
    if (id != null && id is! int) {
      return _validationError(
        'schedule_notification',
        'Invalid "id": expected an integer.',
      );
    }

    final resolvedId = id is int
        ? id
        : DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

    return _runNative(
      command: 'schedule_notification',
      operation: () => gateway.scheduleNotification(
        id: resolvedId,
        title: cleanTitle,
        body: body as String?,
        delay: Duration(seconds: delaySeconds as int? ?? 0),
      ),
    );
  }

  /// Validates and launches an absolute URI.
  Future<SystemResponse> _handleOpenUrl(Map<String, dynamic> parameters) async {
    final url = parameters['url'];
    if (url is! String || url.trim().isEmpty) {
      return _validationError(
        'open_url',
        'Missing or invalid "url". Provide an absolute URI.',
      );
    }

    final cleanUrl = url.trim();
    if (cleanUrl.contains(RegExp(r'\s'))) {
      return _validationError(
        'open_url',
        'Invalid URL "$cleanUrl": whitespace is not permitted.',
      );
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !_uriSchemePattern.hasMatch(uri.scheme)) {
      return _validationError(
        'open_url',
        'Invalid URL "$cleanUrl": expected an absolute URI with a scheme, e.g. "https://example.com".',
      );
    }

    return _runNative(
      command: 'open_url',
      operation: () async {
        final launched = await gateway.openUrl(cleanUrl);
        if (!launched) {
          throw PlatformActionFailureException(
            'No application is available to open "$cleanUrl".',
          );
        }
      },
    );
  }

  /// Validates and copies text to the clipboard.
  Future<SystemResponse> _handleCopyToClipboard(
    Map<String, dynamic> parameters,
  ) async {
    final text = parameters['text'];
    if (text is! String || text.isEmpty) {
      return _validationError(
        'copy_to_clipboard',
        'Missing or invalid "text". Provide non-empty text to copy.',
      );
    }

    return _runNative(
      command: 'copy_to_clipboard',
      operation: () => gateway.copyToClipboard(text),
    );
  }

  /// Executes [operation] and translates gateway failures into the standard
  /// system-response error contract.
  Future<SystemResponse> _runNative({
    required String command,
    required Future<void> Function() operation,
  }) async {
    try {
      await operation();
      return SystemResponse.success(
        command: command,
        data: {'status': 'success', 'action': command},
      );
    } on PlatformPermissionException catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: 'Permission denied for ${e.permission}.',
      );
    } on PlatformActionUnsupportedException catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: e.message,
      );
    } on PlatformActionFailureException catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: e.message,
      );
    } catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: 'Failed to execute $command: $e',
      );
    }
  }

  /// Builds a structured error response for payload validation failures.
  SystemResponse _validationError(String command, String message) {
    return SystemResponse.error(
      command: command,
      errorMessage: 'Validation error for $command: $message',
    );
  }
}
