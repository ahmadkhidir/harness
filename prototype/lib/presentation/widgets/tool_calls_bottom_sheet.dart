import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models/tool_execution_record.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Opens the modal bottom sheet displaying the list of executed tools and their details.
void showToolCallsBottomSheet(
  BuildContext context,
  List<ToolExecutionRecord> toolCalls,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (modalContext) => ToolCallsBottomSheet(toolCalls: toolCalls),
  );
}

/// Modal bottom sheet widget displaying the commands called during a turn and their execution details.
class ToolCallsBottomSheet extends StatelessWidget {
  final List<ToolExecutionRecord> toolCalls;

  const ToolCallsBottomSheet({
    super.key,
    required this.toolCalls,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Modal header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HarnessSpace.lg,
              HarnessSpace.lg,
              HarnessSpace.sm,
              HarnessSpace.sm,
            ),
            child: Row(
              children: [
                Icon(
                  HarnessIcons.terminal,
                  size: HarnessSize.iconMd,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: HarnessSpace.sm),
                Text(
                  'Tool executions',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: HarnessSpace.sm),
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HarnessSpace.sm,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.c100,
                    borderRadius: BorderRadius.circular(HarnessRadius.xs),
                  ),
                  child: Text(
                    '${toolCalls.length}',
                    style: HarnessType.label.copyWith(
                      color: colors.primary.c900,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(HarnessIcons.x),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          // Scrollable tool calls list
          Flexible(
            child: toolCalls.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(HarnessSpace.xl),
                    child: Center(
                      child: Text(
                        'No tools were dispatched in this turn.',
                        style: HarnessType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(HarnessSpace.lg),
                    shrinkWrap: true,
                    itemCount: toolCalls.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: HarnessSpace.md),
                    itemBuilder: (context, index) {
                      return _ToolCallCard(record: toolCalls[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  final ToolExecutionRecord record;

  const _ToolCallCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = HarnessColors.of(context);
    final call = record.call;

    final Color statusColor;
    final Color statusBackground;
    final Color statusBorder;
    final Widget statusIcon;
    final String statusLabel;

    if (record.isRunning) {
      statusColor = colors.primary.c700;
      statusBackground = colors.primary.c100;
      statusBorder = colors.primary.c300;
      statusIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.primary.c500,
        ),
      );
      statusLabel = 'Running';
    } else if (record.isSuccess) {
      statusColor = colors.success.c700;
      statusBackground = colors.success.c100;
      statusBorder = colors.success.c300;
      statusIcon = Icon(
        HarnessIcons.success,
        size: HarnessSize.iconSm,
        color: statusColor,
      );
      statusLabel = 'Success';
    } else {
      statusColor = colors.error.c700;
      statusBackground = colors.error.c100;
      statusBorder = colors.error.c300;
      statusIcon = Icon(
        HarnessIcons.error,
        size: HarnessSize.iconSm,
        color: statusColor,
      );
      statusLabel = 'Failed';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: HarnessRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(HarnessSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command name and status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  call.command,
                  style: HarnessType.codeSm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HarnessSpace.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(HarnessRadius.xs),
                  border: Border.all(color: statusBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusIcon,
                    const SizedBox(width: HarnessSpace.xs),
                    Text(
                      statusLabel,
                      style: HarnessType.label.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HarnessSpace.sm),

          // Parameters section
          _SectionLabel(label: 'Parameters', colors: colors),
          const SizedBox(height: HarnessSpace.xs),
          _CodeBlock(
            text: call.parameters.isEmpty
                ? 'None'
                : const JsonEncoder.withIndent('  ').convert(call.parameters),
            colors: colors,
          ),

          // Output / Observation / Error section
          if (record.isError && record.errorMessage != null) ...[
            const SizedBox(height: HarnessSpace.sm),
            _SectionLabel(
              label: 'Error details',
              colors: colors,
              color: colors.error.c700,
            ),
            const SizedBox(height: HarnessSpace.xs),
            _CodeBlock(
              text: record.errorMessage!,
              colors: colors,
              background: colors.error.c100,
              borderColor: colors.error.c300,
              textColor: colors.error.c900,
            ),
          ] else if (record.output != null) ...[
            const SizedBox(height: HarnessSpace.sm),
            _SectionLabel(label: 'Observation output', colors: colors),
            const SizedBox(height: HarnessSpace.xs),
            _CodeBlock(
              text: record.output is String
                  ? record.output as String
                  : const JsonEncoder.withIndent('  ').convert(record.output),
              colors: colors,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small section heading inside a tool card.
class _SectionLabel extends StatelessWidget {
  final String label;
  final HarnessColors colors;
  final Color? color;

  const _SectionLabel({
    required this.label,
    required this.colors,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: HarnessType.label.copyWith(
        color: color ?? colors.textSecondary,
      ),
    );
  }
}

/// Monospace observation block.
class _CodeBlock extends StatelessWidget {
  final String text;
  final HarnessColors colors;
  final Color? background;
  final Color? borderColor;
  final Color? textColor;

  const _CodeBlock({
    required this.text,
    required this.colors,
    this.background,
    this.borderColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HarnessSpace.sm),
      decoration: BoxDecoration(
        color: background ?? colors.surface,
        borderRadius: HarnessRadius.smAll,
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: SelectableText(
        text,
        style: HarnessType.codeSm.copyWith(
          color: textColor ?? colors.textPrimary,
        ),
      ),
    );
  }
}
