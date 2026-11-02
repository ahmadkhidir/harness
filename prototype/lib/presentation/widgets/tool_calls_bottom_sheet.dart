import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/models/tool_execution_record.dart';

/// Opens the modal bottom sheet displaying the list of executed tools and their details.
void showToolCallsBottomSheet(
  BuildContext context,
  List<ToolExecutionRecord> toolCalls,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Modal header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tool Executions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${toolCalls.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable tool calls list
          Flexible(
            child: toolCalls.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No tools were dispatched in this turn.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    itemCount: toolCalls.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
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
    final theme = Theme.of(context);
    final call = record.call;

    Color statusColor;
    Widget statusIcon;
    String statusLabel;

    if (record.isRunning) {
      statusColor = theme.colorScheme.primary;
      statusIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: statusColor,
        ),
      );
      statusLabel = 'Running';
    } else if (record.isSuccess) {
      statusColor = Colors.green.shade700;
      statusIcon = Icon(Icons.check_circle_outline, size: 16, color: statusColor);
      statusLabel = 'Success';
    } else {
      statusColor = theme.colorScheme.error;
      statusIcon = Icon(Icons.error_outline, size: 16, color: statusColor);
      statusLabel = 'Failed';
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command name and status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  call.command,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusIcon,
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Parameters section
          Text(
            'Parameters',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: SelectableText(
              call.parameters.isEmpty
                  ? 'None'
                  : const JsonEncoder.withIndent('  ').convert(call.parameters),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),

          // Output / Observation / Error section
          if (record.isError && record.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error Details',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: SelectableText(
                record.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ] else if (record.output != null) ...[
            const SizedBox(height: 8),
            Text(
              'Observation Output',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: SelectableText(
                record.output is String
                    ? record.output as String
                    : const JsonEncoder.withIndent('  ').convert(record.output),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
