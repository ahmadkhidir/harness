import 'package:equatable/equatable.dart';
import '../../core/engine/engine_events.dart';

/// Base event class for [HarnessSessionBloc].
abstract class HarnessSessionEvent extends Equatable {
  const HarnessSessionEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched to initialize or load a session workspace.
class InitializeSessionEvent extends HarnessSessionEvent {
  final String? sessionId;

  const InitializeSessionEvent({this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

/// Dispatched to switch the active session and load its turns into the chat UI.
class SwitchSessionEvent extends HarnessSessionEvent {
  final String sessionId;

  const SwitchSessionEvent(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

/// Dispatched when the user submits a new prompt to execute.
class SubmitUserPromptEvent extends HarnessSessionEvent {
  final String prompt;
  final String? apiKey;

  const SubmitUserPromptEvent(this.prompt, {this.apiKey});

  @override
  List<Object?> get props => [prompt, apiKey];
}

/// Dispatched to cancel an active turn in progress.
class CancelActiveTurnEvent extends HarnessSessionEvent {
  const CancelActiveTurnEvent();
}

/// Dispatched when a user taps an interactive A2UI component.
///
/// The [action] is the raw action string configured on the component (for
/// example `platform:set_alarm` or `confirm_choice`), and [dataModel] is the
/// component payload resolved by the A2UI surface renderer.
class HandleA2UIActionEvent extends HarnessSessionEvent {
  /// Raw action declared on the A2UI component.
  final String action;

  /// Payload bound to the component when the action fired.
  final Map<String, dynamic> dataModel;

  const HandleA2UIActionEvent({
    required this.action,
    required this.dataModel,
  });

  @override
  List<Object?> get props => [action, dataModel];
}

/// Dispatched internally as the engine stream yields progressive execution events.
class SessionEngineProgressReceived extends HarnessSessionEvent {
  final EngineProgressEvent progressEvent;

  const SessionEngineProgressReceived(this.progressEvent);

  @override
  List<Object?> get props => [progressEvent];
}

