import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../core/models/turn.dart';
import '../../modules/a2ui/a2ui_surface_store.dart';
import '../../modules/a2ui/widgets/a2ui_surface_view.dart';
import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';
import 'tool_calls_bottom_sheet.dart';

/// Renders a conversational chat bubble for user prompts and agent responses.
///
/// Implements the MessageBubble specification in `docs/Harness/screens.md`:
/// - Aligns user messages to the trailing edge, agent messages to the leading
///   edge, and distinguishes them with surface and label rather than a large
///   accent fill. Teal is reserved for work in progress.
/// - Renders agent text as Markdown and commands as Geist Mono.
/// - Supports long-press copy to clipboard.
class MessageBubble extends StatelessWidget {
  final Turn turn;

  /// Live surface associated with this turn, resolved from the session store.
  final A2UISurfaceState? a2uiSurface;

  /// Whether this bubble is the permanent slot that mounts [a2uiSurface].
  ///
  /// A surface is keyed by `surfaceId` and updated in place for the life of the
  /// session. Only the first turn that introduces a surface renders it; every
  /// later turn for the same ID is invisible in the chat stream. Defaults to
  /// `true` for standalone use.
  final bool isA2UISurfaceAnchor;

  /// Whether the model is currently executing a turn.
  ///
  /// The anchored surface uses this to clear a component's pending state when
  /// the model finishes, so a clicked button does not stay disabled forever.
  final bool isModelExecuting;

  /// Optional callback invoked when a stateful A2UI component changes value
  /// without dispatching an action.
  final void Function(String path, dynamic value)? onA2UIValueChanged;

  /// Optional callback invoked when an embedded A2UI component fires an action.
  ///
  /// The chat screen forwards this to [HandleA2UIActionEvent] so the action is
  /// sent directly to the model as the current user request.
  final void Function(
    String componentId,
    String action,
    Map<String, dynamic> dataModel,
  )? onA2UIAction;

  const MessageBubble({
    super.key,
    required this.turn,
    this.a2uiSurface,
    this.isA2UISurfaceAnchor = true,
    this.isModelExecuting = false,
    this.onA2UIValueChanged,
    this.onA2UIAction,
  });

  bool get isUser => turn.sender == 'user';

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: turn.text ?? ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A2UI turns are pure surfaces, not chat bubbles. Only the anchor turn
    // renders the surface; every later A2UI turn for the same surfaceId is
    // intentionally invisible because it mutates that anchored surface.
    if (turn.isA2UI) {
      if (!isA2UISurfaceAnchor) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colors = HarnessColors.of(context);
      final timeStr = DateFormat('h:mm a').format(turn.timestamp.toLocal());
      final surface = a2uiSurface;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HarnessSpace.lg,
          vertical: HarnessSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, theme, timeStr),
            const SizedBox(height: HarnessSpace.xs),
            if (surface == null || surface.isDeleted)
              Text(
                'Surface removed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              A2UISurfaceView(
                surface: surface,
                isModelExecuting: isModelExecuting,
                onAction: onA2UIAction,
                onValueChanged: onA2UIValueChanged,
              ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);
    final timeStr = DateFormat('h:mm a').format(turn.timestamp.toLocal());

    final bubbleColor = isUser ? colors.surfaceSecondary : colors.surface;
    final textColor = colors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HarnessSpace.lg,
        vertical: HarnessSpace.sm,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _buildHeader(context, theme, timeStr),
          const SizedBox(height: HarnessSpace.xs),
          GestureDetector(
            onLongPress: () => _copyToClipboard(context),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: HarnessSpace.md,
                vertical: HarnessSpace.sm + 2,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(HarnessRadius.md),
                  topRight: const Radius.circular(HarnessRadius.md),
                  bottomLeft: isUser
                      ? const Radius.circular(HarnessRadius.md)
                      : const Radius.circular(HarnessRadius.xs),
                  bottomRight: isUser
                      ? const Radius.circular(HarnessRadius.xs)
                      : const Radius.circular(HarnessRadius.md),
                ),
                border: Border.all(color: colors.border),
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

  /// Builds the sender/time row, including the completed tool-call inspector
  /// when the turn has tool activity. Shared by text bubbles and anchored A2UI
  /// surfaces so tool history remains inspectable without restoring the chat
  /// bubble around a surface.
  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    String timeStr,
  ) {
    final colors = HarnessColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isUser) ...[
            const HarnessMark(
              size: 16,
              semanticLabel: 'Harness',
            ),
            const SizedBox(width: HarnessSpace.xs + 2),
          ],
          Text(
            isUser ? 'You' : 'Harness',
            style: HarnessType.label.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: HarnessSpace.sm),
          Text(
            timeStr,
            style: HarnessType.label.copyWith(
              color: colors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          if (!isUser && turn.toolCalls.isNotEmpty) ...[
            const SizedBox(width: HarnessSpace.xs),
            IconButton(
              key: ValueKey('turn_tool_calls_button_${turn.id}'),
              icon: const Icon(HarnessIcons.chevronDown),
              iconSize: HarnessSize.iconSm,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: HarnessSize.touchTarget,
                minHeight: HarnessSize.touchTarget,
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
    );
  }

  Widget _buildAgentContent(
    BuildContext context,
    ThemeData theme,
    Color textColor,
  ) {
    final colors = HarnessColors.of(context);
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      a: theme.textTheme.bodyMedium?.copyWith(
        color: colors.primary.c500,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary.c500,
      ),
      h1: theme.textTheme.titleLarge,
      h2: theme.textTheme.titleMedium,
      h3: theme.textTheme.titleSmall,
      strong: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
      em: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      blockquote: theme.textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.primary.c300, width: 2),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: HarnessSpace.md),
      code: HarnessType.codeSm.copyWith(
        color: colors.textPrimary,
        backgroundColor: colors.surfaceSecondary,
      ),
      codeblockPadding: const EdgeInsets.all(HarnessSpace.md),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: HarnessRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
    );

    return MarkdownBody(
      data: turn.text ?? '',
      selectable: true,
      styleSheet: styleSheet,
    );
  }
}
