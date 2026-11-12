import 'package:flutter/material.dart';

import '../../core/models/skill_metadata.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Shows a searchable sheet of installed skills and returns the chosen one.
Future<SkillMetadata?> showSkillPickerSheet(
  BuildContext context,
  List<SkillMetadata> skills,
) {
  return showModalBottomSheet<SkillMetadata>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.72,
      child: _SkillPickerSheet(skills: skills),
    ),
  );
}

class _SkillPickerSheet extends StatefulWidget {
  final List<SkillMetadata> skills;

  const _SkillPickerSheet({required this.skills});

  @override
  State<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<_SkillPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);
    final skills = widget.skills.where((skill) {
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return skill.name.toLowerCase().contains(query) ||
          skill.description.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HarnessSpace.lg,
            HarnessSpace.sm,
            HarnessSpace.lg,
            HarnessSpace.sm,
          ),
          child: Text(
            'Insert a skill',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HarnessSpace.lg),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: HarnessType.body,
            decoration: InputDecoration(
              hintText: 'Search skills',
              prefixIcon: const Icon(HarnessIcons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: HarnessSpace.sm),
        Expanded(
          child: skills.isEmpty
              ? Center(
                  child: Text(
                    widget.skills.isEmpty
                        ? 'No skills installed yet.'
                        : 'No skills match "$_query".',
                    style: HarnessType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: skills.length,
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    return ListTile(
                      leading: const Icon(HarnessIcons.skill),
                      title: Text(
                        '/${skill.name}',
                        style: HarnessType.code.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HarnessType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      trailing: Text(
                        'v${skill.version}',
                        style: HarnessType.label.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(skill),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
