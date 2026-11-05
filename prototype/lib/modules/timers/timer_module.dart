import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/services/timer_service.dart';
import '../base/harness_module.dart';

/// Exposes scheduled self-prompt timers as harness commands (FEAT-010).
///
/// A timer delivers its prompt back to the same session after a delay. The
/// fired prompt is treated as user-triggered input and does not create a chat
/// turn.
class TimerModule extends HarnessModule {
  /// Timer persistence and execution service.
  final TimerService timerService;

  /// Creates a module backed by [timerService].
  TimerModule({required this.timerService});

  /// Maximum prompt length accepted for a timer.
  static const int maxPromptLength = 2000;

  /// Maximum number of pending timers per session.
  static const int maxPendingTimers = 10;

  /// Maximum delay accepted for a timer.
  static const int maxDelaySeconds = 604800;

  @override
  String get moduleName => 'timers';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'schedule_timer',
          description:
              'Schedules a prompt to be sent back to this session after a delay. The fired prompt runs a normal agent turn but does not appear as a chat message.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'prompt': {
                'type': 'string',
                'minLength': 1,
                'maxLength': maxPromptLength,
                'description': 'Prompt delivered back to the agent when the timer fires.',
              },
              'delaySeconds': {
                'type': 'integer',
                'minimum': 1,
                'maximum': maxDelaySeconds,
                'description': 'Seconds to wait before firing the prompt.',
              },
              'label': {
                'type': 'string',
                'maxLength': 64,
                'description': 'Optional user-facing timer label.',
              },
            },
            'required': ['prompt', 'delaySeconds'],
          },
        ),
        CommandDefinition(
          command: 'cancel_timer',
          description: 'Cancels a pending scheduled timer by ID.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'timerId': {
                'type': 'string',
                'description': 'Timer identifier returned by schedule_timer.',
              },
            },
            'required': ['timerId'],
          },
        ),
        CommandDefinition(
          command: 'list_timers',
          description:
              'Lists pending timers for the current session, ordered by firing time.',
          parametersSchema: const {'type': 'object'},
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final sessionId = HarnessFileSystem.instance?.activeSessionId;
    if (sessionId == null) {
      return SystemResponse.error(
        command: command,
        errorMessage: 'No active session is available for timer scheduling.',
      );
    }

    switch (command) {
      case 'schedule_timer':
        return _handleSchedule(sessionId, parameters);
      case 'cancel_timer':
        return _handleCancel(sessionId, parameters);
      case 'list_timers':
        return _handleList(sessionId);
      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unrecognized timer command: "$command".',
        );
    }
  }

  Future<SystemResponse> _handleSchedule(
    String sessionId,
    Map<String, dynamic> parameters,
  ) async {
    final prompt = parameters['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      return _validationError(
        'schedule_timer',
        'Missing or invalid "prompt". Provide the text to send back to the agent.',
      );
    }
    if (prompt.length > maxPromptLength) {
      return _validationError(
        'schedule_timer',
        'Prompt must be $maxPromptLength characters or fewer.',
      );
    }

    final delaySeconds = parameters['delaySeconds'];
    if (delaySeconds is! int ||
        delaySeconds < 1 ||
        delaySeconds > maxDelaySeconds) {
      return _validationError(
        'schedule_timer',
        'Invalid "delaySeconds": expected an integer between 1 and $maxDelaySeconds.',
      );
    }

    final label = parameters['label'];
    if (label != null && label is! String) {
      return _validationError(
        'schedule_timer',
        'Invalid "label": expected a string.',
      );
    }
    if (label is String && label.length > 64) {
      return _validationError(
        'schedule_timer',
        'Label must be 64 characters or fewer.',
      );
    }

    try {
      final pending = await timerService.list(sessionId);
      if (pending.length >= maxPendingTimers) {
        return SystemResponse.error(
          command: 'schedule_timer',
          errorMessage:
              'This session already has $maxPendingTimers pending timers. Cancel one before scheduling another.',
        );
      }

      final timer = await timerService.schedule(
        sessionId: sessionId,
        prompt: prompt.trim(),
        delay: Duration(seconds: delaySeconds),
        label: label is String && label.trim().isNotEmpty ? label.trim() : null,
      );

      return SystemResponse.success(
        command: 'schedule_timer',
        data: {
          'timerId': timer.id,
          'sessionId': timer.sessionId,
          'firesAt': timer.firesAt.toIso8601String(),
        },
      );
    } catch (e) {
      return SystemResponse.error(
        command: 'schedule_timer',
        errorMessage: 'Could not schedule timer: $e',
      );
    }
  }

  Future<SystemResponse> _handleCancel(
    String sessionId,
    Map<String, dynamic> parameters,
  ) async {
    final timerId = parameters['timerId'];
    if (timerId is! String || timerId.trim().isEmpty) {
      return _validationError(
        'cancel_timer',
        'Missing or invalid "timerId".',
      );
    }

    final cancelled = await timerService.cancel(sessionId, timerId.trim());
    if (!cancelled) {
      return SystemResponse.error(
        command: 'cancel_timer',
        errorMessage:
            'Timer "${timerId.trim()}" was not found or is no longer pending.',
      );
    }

    return SystemResponse.success(
      command: 'cancel_timer',
      data: {'timerId': timerId.trim(), 'status': 'cancelled'},
    );
  }

  Future<SystemResponse> _handleList(String sessionId) async {
    final timers = await timerService.list(sessionId);
    return SystemResponse.success(
      command: 'list_timers',
      data: {
        'timers': timers
            .map((timer) => {
                  'timerId': timer.id,
                  'prompt': timer.prompt,
                  if (timer.label != null) 'label': timer.label,
                  'firesAt': timer.firesAt.toIso8601String(),
                  'status': timer.status.name,
                })
            .toList(),
      },
    );
  }

  SystemResponse _validationError(String command, String message) {
    return SystemResponse.error(
      command: command,
      errorMessage: 'Validation error for $command: $message',
    );
  }
}
