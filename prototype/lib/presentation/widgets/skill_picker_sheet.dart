import 'package:flutter/material.dart';

import '../../core/models/skill_metadata.dart';

/// Shows a searchable sheet of installed skills and returns the chosen one.
Future<SkillMetadata?> showSkillPickerSheet(
  BuildContext context,
  List<SkillMetadata> skills,
) {
  return showModalBottomSheet<SkillMetadata>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Insert a skill',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search skills',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: skills.isEmpty
              ? Center(
                  child: Text(
                    widget.skills.isEmpty
                        ? 'No skills installed yet.'
                        : 'No skills match "$_query".',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: skills.length,
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    return ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: Text('/${skill.name}'),
                      subtitle: Text(
                        skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        'v${skill.version}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
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
