import 'package:flutter/material.dart';

import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Informational placeholder screen for routes whose full features have not yet been implemented.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String featureName;
  final String description;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.featureName,
    this.description =
        'This capability will be fully implemented when its milestone feature is activated.',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(HarnessSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HarnessMark(size: 48, accented: true),
              const SizedBox(height: HarnessSpace.lg),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HarnessSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HarnessSpace.sm,
                  vertical: HarnessSpace.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.c100,
                  borderRadius: BorderRadius.circular(HarnessRadius.xs),
                ),
                child: Text(
                  featureName,
                  style: HarnessType.label.copyWith(color: colors.primary.c900),
                ),
              ),
              const SizedBox(height: HarnessSpace.md),
              Text(
                description,
                style: HarnessType.bodySm.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HarnessSpace.xl),
              OutlinedButton.icon(
                icon: const Icon(
                  HarnessIcons.arrowLeft,
                  size: HarnessSize.iconSm,
                ),
                label: const Text('Back to chat'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
