import 'package:equatable/equatable.dart';
import '../../core/engine/engine_events.dart';
import '../../core/models/scheduled_timer.dart';

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
/// The [action] is the action string configured on the component, [dataModel]
/// is the surface data model after the interaction, and [surfaceId] identifies
/// the surface that owns the component.
class HandleA2UIActionEvent extends HarnessSessionEvent {
  /// Surface that owns the component.
  final String surfaceId;

  /// Component that fired the action.
  final String componentId;

  /// Action declared on the A2UI component.
  final String action;

  /// Surface data model after the component interaction.
  final Map<String, dynamic> dataModel;

  const HandleA2UIActionEvent({
    required this.surfaceId,
    required this.componentId,
    required this.action,
    required this.dataModel,
  });

  @override
  List<Object?> get props => [surfaceId, componentId, action, dataModel];
}

/// Dispatched when a stateful A2UI component changes value without starting a
/// model turn.
///
/// Used for in-progress input state such as typing in a text field or dragging
/// a slider. The value is written to the live surface data model so bindings
/// update immediately.
class UpdateA2UISurfaceDataEvent extends HarnessSessionEvent {
  /// Surface that owns the component.
  final String surfaceId;

  /// RFC 6901 JSON Pointer path to update.
  final String path;

  /// New value at [path].
  final dynamic value;

  const UpdateA2UISurfaceDataEvent({
    required this.surfaceId,
    required this.path,
    required this.value,
  });

  @override
  List<Object?> get props => [surfaceId, path, value];
}

/// Dispatched when a scheduled timer becomes due and should run its prompt.
class RunScheduledTimerEvent extends HarnessSessionEvent {
  /// The due timer.
  final ScheduledTimer timer;

  const RunScheduledTimerEvent(this.timer);

  @override
  List<Object?> get props => [timer];
}

/// Dispatched internally as the engine stream yields progressive execution events.
class SessionEngineProgressReceived extends HarnessSessionEvent {
  final EngineProgressEvent progressEvent;

  const SessionEngineProgressReceived(this.progressEvent);

  @override
  List<Object?> get props => [progressEvent];
}

