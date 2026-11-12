import 'package:flutter/material.dart';

import '../bloc/harness_session_state.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Visual indicator pill displaying real-time execution status of a system tool call.
///
/// A running call carries a moving indicator, a completed call a check, and a
/// failed call an alert mark. Color is never the only signal, and the command
/// itself is set in Geist Mono because it is code, not prose.
class SystemCallPill extends StatelessWidget {
  final ToolExecutionIndicator indicator;

  const SystemCallPill({
    super.key,
    required this.indicator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = HarnessColors.of(context);
    final isRunning = indicator.isRunning;
    final isSuccess = indicator.isSuccess;

    final Color background;
    final Color foreground;
    final Color border;
    final Widget icon;

    if (isRunning) {
      background = colors.primary.c100;
      foreground = colors.primary.c700;
      border = colors.primary.c300;
      icon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.primary.c500,
        ),
      );
    } else if (isSuccess) {
      background = colors.success.c100;
      foreground = colors.success.c700;
      border = colors.success.c300;
      icon = Icon(
        HarnessIcons.success,
        size: 14,
        color: colors.success.c700,
      );
    } else {
      background = colors.error.c100;
      foreground = colors.error.c700;
      border = colors.error.c300;
      icon = Icon(
        HarnessIcons.error,
        size: 14,
        color: colors.error.c700,
      );
    }

    return Container(
      height: HarnessSize.pill,
      margin: const EdgeInsets.symmetric(horizontal: HarnessSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: HarnessSpace.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(HarnessRadius.xs),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: HarnessSpace.xs + 2),
          Text(
            indicator.call.command,
            style: HarnessType.codeSm.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
