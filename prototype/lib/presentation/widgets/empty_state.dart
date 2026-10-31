import 'package:flutter/material.dart';

/// Shared empty state placeholder displayed when a conversation or list contains zero records.
///
/// Implements the EmptyState component from `docs/Harness/screens.md`.
class EmptyState extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final List<String> suggestionChips;
  final ValueChanged<String>? onSelectPrompt;

  const EmptyState({
    super.key,
    this.title = 'Welcome to Harness',
    this.description =
        'An autonomous, mobile-first agent runtime. Ask a question or assign a multi-step task to begin.',
    this.icon = Icons.smart_toy_outlined,
    this.suggestionChips = const [
      'Check system status',
      'What commands can you execute?',
      'Inspect sandboxed workspace',
    ],
    this.onSelectPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (suggestionChips.isNotEmpty) ...[
              Text(
                'Suggestions',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestionChips.map((chipText) {
                  return ActionChip(
                    label: Text(chipText),
                    onPressed: () => onSelectPrompt?.call(chipText),
                    avatar: const Icon(Icons.arrow_outward_rounded, size: 16),
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

