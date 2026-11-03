import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../core/models/turn.dart';
import '../../modules/a2ui/widgets/a2ui_surface_view.dart';
import 'tool_calls_bottom_sheet.dart';

/// Renders a conversational chat bubble for user prompts and agent responses.
///
/// Implements the MessageBubble specification in `docs/Harness/screens.md`:
/// - Aligns user messages to the trailing edge with primary accent styling.
/// - Aligns agent messages to the leading edge with surface styling and Markdown rendering.
/// - Supports long-press copy to clipboard.
class MessageBubble extends StatelessWidget {
  final Turn turn;

  /// Optional callback invoked when an embedded A2UI component fires an action.
  ///
  /// The chat screen forwards this to [HandleA2UIActionEvent] so platform
  /// actions execute directly and conversational actions become new turns.
  final void Function(String action, Map<String, dynamic> dataModel)?
      onA2UIAction;

  const MessageBubble({
    super.key,
    required this.turn,
    this.onA2UIAction,
  });

  bool get isUser => turn.sender == 'user';

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: turn.text ?? ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('h:mm a').format(turn.timestamp.toLocal());

    final bubbleColor = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    final textColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser ? 'You' : 'Harness Agent',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline.withValues(alpha: 0.8),
                  ),
                ),
                if (!isUser && turn.toolCalls.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('turn_tool_calls_button_${turn.id}'),
                    icon: const Icon(Icons.expand_more),
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    tooltip: 'Show tool calls (${turn.toolCalls.length})',
                    onPressed: () => showToolCallsBottomSheet(
                      context,
                      turn.toolCalls,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: () => _copyToClipboard(context),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: isUser
                  ? SelectableText(
                      turn.text ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                      ),
                    )
                  : _buildAgentContent(context, theme, textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentContent(
    BuildContext context,
    ThemeData theme,
    Color textColor,
  ) {
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.7),
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
    );

    if (turn.isA2UI) {
      final hasText = turn.text != null && turn.text!.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasText) ...[
            MarkdownBody(
              data: turn.text!.trim(),
              selectable: true,
              styleSheet: styleSheet,
            ),
            const SizedBox(height: 8),
          ],
          A2UISurfaceView(
            payload: turn.a2uiPayload,
            onAction: onA2UIAction,
          ),
        ],
      );
    }

    return MarkdownBody(
      data: turn.text ?? '',
      selectable: true,
      styleSheet: styleSheet,
    );
  }
}
