import 'dart:convert';

/// Builds the deterministic user prompt for an A2UI component action.
///
/// The prompt carries the action name and the surface data model so the model
/// can continue the conversation with the current component state. The wording
/// deliberately avoids UI keywords such as "A2UI" or "button" because the
/// engine treats those words as a request to deliver a widget surface, which
/// would incorrectly force the next turn into UI mode.
String buildA2UIActionPrompt({
  required String surfaceId,
  required String componentId,
  required String action,
  required Map<String, dynamic> payload,
}) {
  final buffer = StringBuffer(
    'The user selected the option "$action" '
    '(component "$componentId", surface "$surfaceId").',
  );
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
