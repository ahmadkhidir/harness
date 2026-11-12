import 'package:flutter/material.dart';

import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Empty-session state shown before the first turn.
///
/// The brand mark replaces a pictogram icon: the frame and resting threads sit
/// in secondary ink while the one raised thread carries the accent, following
/// the one-active-line illustration direction in `docs/Harness/branding.md`.
class EmptyState extends StatelessWidget {
  /// Welcome heading.
  final String title;

  /// One-sentence explanation of what the screen does.
  final String description;

  /// Prompt suggestions that submit directly when tapped.
  final List<String> suggestionChips;

  /// Callback for a tapped suggestion.
  final ValueChanged<String>? onSelectPrompt;

  const EmptyState({
    super.key,
    this.title = 'Ready for a task',
    this.description =
        'Ask a question or assign a multi-step job. Tool calls, results, and failures appear here as they happen.',
    this.suggestionChips = const [
      'Check system status',
      'What commands can you execute?',
      'Inspect sandboxed workspace',
    ],
    this.onSelectPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = HarnessColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: HarnessSpace.xxl,
          vertical: HarnessSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HarnessMark(
              size: 56,
              accented: true,
            ),
            const SizedBox(height: HarnessSpace.xl),
            Text(
              title,
              style: textTheme.headlineSmall?.copyWith(
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HarnessSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                description,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (suggestionChips.isNotEmpty) ...[
              const SizedBox(height: HarnessSpace.xl),
              Text(
                'Start with',
                style: HarnessType.label.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: HarnessSpace.md),
              Wrap(
                spacing: HarnessSpace.sm,
                runSpacing: HarnessSpace.sm,
                alignment: WrapAlignment.center,
                children: suggestionChips.map((chipText) {
                  return ActionChip(
                    label: Text(chipText),
                    onPressed: () => onSelectPrompt?.call(chipText),
                    avatar: Icon(
                      HarnessIcons.arrowUpRight,
                      size: HarnessSize.iconSm,
                      color: colors.textSecondary,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
