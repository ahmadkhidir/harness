import 'package:flutter/material.dart';
import '../bloc/harness_session_state.dart';

/// Visual indicator pill displaying real-time execution status of a system tool call.
///
/// Used in the chat stream during turn execution to provide immediate visual feedback
/// as parallel tools start and finish (`read_file ⏳`, `read_file ✓`, `web_search ✗`).
class SystemCallPill extends StatelessWidget {
  final ToolExecutionIndicator indicator;

  const SystemCallPill({
    super.key,
    required this.indicator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = indicator.isRunning;
    final isSuccess = indicator.isSuccess;

    Color backgroundColor;
    Color foregroundColor;
    Widget icon;

    if (isRunning) {
      backgroundColor = theme.colorScheme.surfaceContainerHighest;
      foregroundColor = theme.colorScheme.primary;
      icon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: foregroundColor,
        ),
      );
    } else if (isSuccess) {
      backgroundColor = Colors.green.withValues(alpha: 0.15);
      foregroundColor = Colors.green.shade800;
      icon = Icon(Icons.check_circle, size: 14, color: foregroundColor);
    } else {
      backgroundColor = Colors.red.withValues(alpha: 0.15);
      foregroundColor = Colors.red.shade800;
      icon = Icon(Icons.error_outline, size: 14, color: foregroundColor);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            indicator.call.command,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

