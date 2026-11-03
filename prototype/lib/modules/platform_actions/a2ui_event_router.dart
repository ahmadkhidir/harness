import 'dart:convert';

import '../../core/models/system_response.dart';
import 'platform_actions_module.dart';

/// Classification of an A2UI interactive event.
enum A2UIEventKind {
  /// Event targets a native platform command and should execute immediately.
  platformAction,

  /// Event represents a conversational choice and should become a new user turn.
  conversationTurn,

  /// Event cannot be routed because its action value is malformed.
  invalid,
}

/// Immutable routing decision produced by [A2UIEventRouter].
///
/// The route carries only a plan; executing it is the caller's responsibility so
/// the presentation layer can decide how to surface success, failure, or a new
/// conversational turn.
class A2UIEventRoute {
  /// Classification of this event.
  final A2UIEventKind kind;

  /// Raw action string configured on the A2UI component.
  final String action;

  /// Platform command name when [kind] is [A2UIEventKind.platformAction].
  final String? command;

  /// Parameters merged from the A2UI data model and inline action query string.
  final Map<String, dynamic> parameters;

  /// User prompt text when [kind] is [A2UIEventKind.conversationTurn].
  final String? prompt;

  /// Explanation when [kind] is [A2UIEventKind.invalid].
  final String? errorMessage;

  const A2UIEventRoute._({
    required this.kind,
    required this.action,
    this.command,
    this.parameters = const {},
    this.prompt,
    this.errorMessage,
  });

  /// Builds a platform-action route.
  factory A2UIEventRoute.platform({
    required String action,
    required String command,
    required Map<String, dynamic> parameters,
  }) {
    return A2UIEventRoute._(
      kind: A2UIEventKind.platformAction,
      action: action,
      command: command,
      parameters: Map.unmodifiable(parameters),
    );
  }

  /// Builds a conversational-turn route.
  factory A2UIEventRoute.conversation({
    required String action,
    required String prompt,
    required Map<String, dynamic> parameters,
  }) {
    return A2UIEventRoute._(
      kind: A2UIEventKind.conversationTurn,
      action: action,
      prompt: prompt,
      parameters: Map.unmodifiable(parameters),
    );
  }

  /// Builds an invalid route carrying a model-readable explanation.
  factory A2UIEventRoute.invalid({
    required String action,
    required String errorMessage,
  }) {
    return A2UIEventRoute._(
      kind: A2UIEventKind.invalid,
      action: action,
      errorMessage: errorMessage,
    );
  }
}

/// Routes A2UI interactive component events to native platform actions or new
/// conversational turns.
///
/// Implements FEAT-007 event dispatch semantics:
/// - Actions prefixed with `platform:` execute through [PlatformActionsModule]
///   and never consume an additional LLM turn.
/// - All other actions are converted into a structured user prompt containing
///   the action name and its payload, then submitted as a new engine turn.
///
/// Parameters may be supplied in two complementary ways:
/// 1. In the A2UI surface data model (for example `{"time": "07:00"}`).
/// 2. Inline in the action URI (`platform:set_alarm?time=07:00&label=Flight`).
///    Inline query values take precedence over the data model.
class A2UIEventRouter {
  /// Prefix marking an A2UI action as a direct platform command.
  static const String platformPrefix = 'platform:';

  /// Platform action executor. Null disables native routing while keeping
  /// conversational action routing operational.
  final PlatformActionsModule? platformActions;

  /// Creates a router that dispatches platform actions through [platformActions].
  const A2UIEventRouter({this.platformActions});

  /// Resolves [action] and [dataModel] into an executable route without side
  /// effects.
  A2UIEventRoute resolve(
    String action,
    Map<String, dynamic> dataModel,
  ) {
    final cleanAction = action.trim();
    if (cleanAction.isEmpty) {
      return A2UIEventRoute.invalid(
        action: action,
        errorMessage: 'A2UI action is empty and cannot be routed.',
      );
    }

    final payload = Map<String, dynamic>.from(dataModel);

    if (!cleanAction.startsWith(platformPrefix)) {
      return A2UIEventRoute.conversation(
        action: cleanAction,
        prompt: _buildConversationPrompt(cleanAction, payload),
        parameters: payload,
      );
    }

    final remainder = cleanAction.substring(platformPrefix.length);
    final questionIndex = remainder.indexOf('?');
    final command = (questionIndex == -1
            ? remainder
            : remainder.substring(0, questionIndex))
        .trim();

    if (command.isEmpty) {
      return A2UIEventRoute.invalid(
        action: cleanAction,
        errorMessage:
            'Platform action "$cleanAction" does not name a command after "$platformPrefix".',
      );
    }

    // Query parameters are decoded by Uri.splitQueryString, which also handles
    // percent-encoding such as `time=07%3A00`.
    if (questionIndex != -1) {
      final query = remainder.substring(questionIndex + 1);
      if (query.isNotEmpty) {
        try {
          payload.addAll(Uri.splitQueryString(query));
        } on FormatException {
          return A2UIEventRoute.invalid(
            action: cleanAction,
            errorMessage:
                'Platform action "$cleanAction" contains an invalid query string.',
          );
        }
      }
    }

    return A2UIEventRoute.platform(
      action: cleanAction,
      command: command,
      parameters: payload,
    );
  }

  /// Executes a platform-action route through [PlatformActionsModule].
  ///
  /// Returns a structured error instead of throwing when the router was created
  /// without a platform executor or the route is not a platform action.
  Future<SystemResponse> executePlatform(A2UIEventRoute route) async {
    final command = route.command;
    if (route.kind != A2UIEventKind.platformAction || command == null) {
      return SystemResponse.error(
        command: command ?? 'platform_action',
        errorMessage: 'Route is not a platform action.',
      );
    }

    final module = platformActions;
    if (module == null) {
      return SystemResponse.error(
        command: command,
        errorMessage:
            'Platform actions are unavailable in this session configuration.',
      );
    }

    return module.executeCommand(command, route.parameters);
  }

  /// Formats a conversational action as a deterministic user prompt so the
  /// engine receives both the action name and its structured payload.
  ///
  /// The wording deliberately avoids UI keywords such as "A2UI" or "button"
  /// because the engine treats those words as a request to deliver a widget
  /// surface, which would incorrectly force the next turn into UI mode.
  String _buildConversationPrompt(
    String action,
    Map<String, dynamic> payload,
  ) {
    final buffer = StringBuffer('The user selected the option "$action".');
    if (payload.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln()
        ..writeln('Selected data:')
        ..writeln(jsonEncode(payload));
    }
    buffer
      ..writeln()
      ..write('Continue the conversation using this selection.');
    return buffer.toString();
  }
}
