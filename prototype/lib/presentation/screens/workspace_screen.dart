import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../../core/models/installed_skill_package.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/services/skills_service.dart';
import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Screen 4: Workspace & Skills Explorer.
///
/// Implements `docs/Harness/screens/04-workspace-skills.md`:
/// - Segmented TabBar switching between "Storage Files" and "Installed Skills".
/// - Tab 1 (Storage Files): Hierarchical directory tree, search filter, and file preview sheet
///   with line numbers, copy path action, and large-file (>2MB) truncation.
/// - Tab 2 (Installed Skills): Installed skill cards with version chips, sub-file counters,
///   malformed package warnings, and full SKILL.md markdown preview.
class WorkspaceScreen extends StatefulWidget {
  final HarnessFileSystem? fileSystem;
  final SkillsService? skillsService;

  const WorkspaceScreen({
    super.key,
    this.fileSystem,
    this.skillsService,
  });

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final SkillsService _skillsService;

  bool _isLoading = true;
  String? _errorMessage;
  int _activeTab = 0;

  // Storage files state
  final TextEditingController _fileSearchController = TextEditingController();
  String _fileSearchQuery = '';
  List<WorkspaceFileEntry> _storageFiles = [];

  // Skills state
  List<InstalledSkillPackage> _installedSkills = [];

  HarnessFileSystem? get _fs =>
      widget.fileSystem ?? HarnessFileSystem.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _skillsService =
        widget.skillsService ?? SkillsService(fileSystem: _fs);
    _scanData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _fileSearchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.index != _activeTab) {
      setState(() => _activeTab = _tabController.index);
    }
  }

  void _scanData() {
    try {
      final fs = _fs;
      final fileEntries = <WorkspaceFileEntry>[];

      if (fs != null) {
        for (final tag in fs.mounts.mountTags) {
          try {
            final mountDir = fs.mounts.resolveVirtualDir(tag);
            if (mountDir.existsSync()) {
              _scanDirectoryRecursively(mountDir, tag, '', fileEntries);
            }
          } catch (_) {}
        }
      }

      final skills = _skillsService.scanAllSkillPackages();

      _storageFiles = fileEntries;
      _installedSkills = skills;
      _isLoading = false;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to scan workspace: $e';
      _isLoading = false;
    }
  }

  void _rescan() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _scanData();
    if (mounted) {
      setState(() {});
    }
  }

  /// Imports a skill folder selected from device storage after validation.
  Future<void> _importSkill() async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath();
      if (selectedPath == null || selectedPath.trim().isEmpty) return;

      final source = Directory(selectedPath);
      final validation = _skillsService.validateSkillDirectory(source);
      if (!validation.isValid) {
        await _showImportError(validation.error ?? 'Invalid skill package.');
        return;
      }

      var name = _normalizeSkillName(validation.metadata!.name);
      if (name.isEmpty) {
        await _showImportError('The skill name is empty after sanitization.');
        return;
      }

      var overwrite = false;
      if (_skillsService.skillExists(name)) {
        if (_skillsService.isSkillLocked(name)) {
          await _showImportError(
            'Skill "$name" is built in and cannot be overwritten. '
            'Use its restore action instead.',
          );
          return;
        }
        final choice = await _askConflict(name);
        if (choice == null) return;
        if (choice == _SkillConflictChoice.overwrite) {
          overwrite = true;
        } else {
          final renamed = await _askRename('$name-2');
          if (renamed == null) return;
          name = renamed;
          if (_skillsService.skillExists(name)) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('A skill named "$name" already exists.')),
            );
            return;
          }
        }
      }

      await _skillsService.importSkillPackage(
        source: source,
        name: name,
        overwrite: overwrite,
      );
      _rescan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported skill "$name".')),
      );
    } on SkillAlreadyExistsException catch (e) {
      await _showImportError(e.toString());
    } on SkillLockedException catch (e) {
      await _showImportError(e.toString());
    } on SkillImportException catch (e) {
      await _showImportError(e.message);
    } catch (e) {
      await _showImportError('Could not import skill: $e');
    }
  }

  /// Restores a bundled skill, overwriting any local edits.
  Future<void> _restoreBuiltinSkill(String name) async {
    try {
      await _skillsService.restoreBuiltinSkill(name);
      _rescan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored built-in skill "$name".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not restore "$name": $e')),
      );
    }
  }

  Future<void> _showImportError(String message) {
    if (!mounted) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invalid skill package'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<_SkillConflictChoice?> _askConflict(String name) {
    return showDialog<_SkillConflictChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skill already installed'),
        content: Text(
          'A skill named "$name" already exists. Overwrite it, rename the import, or cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_SkillConflictChoice.rename),
            child: const Text('Rename'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_SkillConflictChoice.overwrite),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askRename(String suggested) async {
    final controller = TextEditingController(text: suggested);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename imported skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Skill name',
            helperText: 'Lower-case letters, numbers, and hyphens.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = _normalizeSkillName(controller.text);
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _normalizeSkillName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  void _scanDirectoryRecursively(
    Directory dir,
    String mountTag,
    String relativePrefix,
    List<WorkspaceFileEntry> results,
  ) {
    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        final name = p.basename(entity.path);
        final currentRel = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        final virtualPath = '$mountTag/$currentRel';

        if (entity is Directory) {
          results.add(WorkspaceFileEntry(
            name: name,
            virtualPath: virtualPath,
            physicalPath: entity.path,
            isDirectory: true,
          ));
          _scanDirectoryRecursively(entity, mountTag, currentRel, results);
        } else if (entity is File) {
          int size = 0;
          try {
            size = entity.lengthSync();
          } catch (_) {}
          results.add(WorkspaceFileEntry(
            name: name,
            virtualPath: virtualPath,
            physicalPath: entity.path,
            isDirectory: false,
            sizeBytes: size,
          ));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
        icon: const Icon(HarnessIcons.arrowLeft),
        tooltip: 'Back',
        onPressed: () => Navigator.maybePop(context),
      ),
      title: const Text('Workspace'),
        actions: [
          if (_activeTab == 1)
            IconButton(
              icon: const Icon(HarnessIcons.importSkill),
              tooltip: 'Import Skill',
              onPressed: _importSkill,
            ),
          IconButton(
            icon: const Icon(HarnessIcons.refresh),
            tooltip: 'Rescan Workspace',
            onPressed: _rescan,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(HarnessIcons.folder),
              text: 'Storage Files',
            ),
            Tab(
              icon: Icon(HarnessIcons.skill),
              text: 'Installed Skills',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorBanner(theme)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStorageFilesTab(theme),
                    _buildInstalledSkillsTab(theme),
                  ],
                ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HarnessIcons.error, size: 48, color: colors.error.c500),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown error',
              style: TextStyle(color: colors.error.c500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HarnessSpace.lg),
            FilledButton.tonal(
              onPressed: _rescan,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: STORAGE FILES
  // ==========================================

  Widget _buildStorageFilesTab(ThemeData theme) {
    final colors = HarnessColors.of(context);
    final filtered = _storageFiles.where((entry) {
      if (entry.isDirectory) return false; // Show files in list
      if (_fileSearchQuery.isEmpty) return true;
      return entry.virtualPath
          .toLowerCase()
          .contains(_fileSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HarnessSpace.lg,
            HarnessSpace.lg,
            HarnessSpace.lg,
            HarnessSpace.sm,
          ),
          child: TextField(
            controller: _fileSearchController,
            style: HarnessType.body,
            decoration: InputDecoration(
              labelText: 'Search storage files',
              prefixIcon: const Icon(HarnessIcons.search),
              suffixIcon: _fileSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(HarnessIcons.x),
                      onPressed: () {
                        setState(() {
                          _fileSearchController.clear();
                          _fileSearchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() {
                _fileSearchQuery = val.trim();
              });
            },
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyStorageView(theme)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HarnessSpace.lg,
                    vertical: HarnessSpace.sm,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: HarnessSpace.sm,
                        vertical: HarnessSpace.xs,
                      ),
                      leading: Icon(
                        _getFileIcon(item.name),
                        color: colors.textSecondary,
                      ),
                      title: Text(
                        item.name,
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        '${item.virtualPath} · ${_formatFileSize(item.sizeBytes)}',
                        style: HarnessType.codeSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        HarnessIcons.chevronRight,
                        size: HarnessSize.iconSm,
                      ),
                      onTap: () => _showFilePreviewSheet(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyStorageView(ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HarnessMark(size: 48, accented: true),
          const SizedBox(height: HarnessSpace.lg),
          Text(
            _fileSearchQuery.isNotEmpty
                ? 'No matching files'
                : 'No files in storage',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: HarnessSpace.sm),
          Text(
            _fileSearchQuery.isNotEmpty
                ? 'Try a different search term.'
                : 'Files saved by the agent or placed in primary/ appear here.',
            style: HarnessType.bodySm.copyWith(
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showFilePreviewSheet(WorkspaceFileEntry entry) {
    final colors = HarnessColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final file = File(entry.physicalPath);

        bool isTruncated = false;
        String content = '';
        const maxSizeBytes = 2 * 1024 * 1024; // 2 MB limit

        try {
          if (file.existsSync()) {
            final length = file.lengthSync();
            if (length > maxSizeBytes) {
              isTruncated = true;
              content = file
                  .readAsLinesSync()
                  .take(500)
                  .join('\n');
            } else {
              content = file.readAsStringSync();
            }
          } else {
            content = '(File no longer exists on disk)';
          }
        } catch (e) {
          content = '(Could not preview file content: $e)';
        }

        final linesList = content.split('\n');
        final sheetHeight = MediaQuery.of(bottomSheetContext).size.height * 0.85;

        return SizedBox(
          height: sheetHeight,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HarnessSpace.lg,
                    HarnessSpace.lg,
                    HarnessSpace.sm,
                    HarnessSpace.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.name,
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              entry.virtualPath,
                              style: HarnessType.codeSm.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          HarnessIcons.copy,
                          size: HarnessSize.iconSm,
                        ),
                        tooltip: 'Copy virtual path',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: entry.virtualPath));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied: ${entry.virtualPath}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(HarnessIcons.x),
                        onPressed: () => Navigator.pop(bottomSheetContext),
                      ),
                    ],
                  ),
                ),
                if (isTruncated)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                      horizontal: HarnessSpace.lg,
                      vertical: HarnessSpace.xs,
                    ),
                    padding: const EdgeInsets.all(HarnessSpace.sm),
                    decoration: BoxDecoration(
                      color: colors.warning.c100,
                      borderRadius: HarnessRadius.smAll,
                      border: Border.all(color: colors.warning.c300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          HarnessIcons.warning,
                          size: HarnessSize.iconSm,
                          color: colors.warning.c700,
                        ),
                        const SizedBox(width: HarnessSpace.sm),
                        Expanded(
                          child: Text(
                            'Large file (> 2 MB): showing first 500 lines.',
                            style: HarnessType.label.copyWith(
                              color: colors.warning.c900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(height: 1, color: colors.border),
                Expanded(
                  child: Container(
                    color: colors.surfaceSecondary,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(HarnessSpace.md),
                      itemCount: linesList.length,
                      itemBuilder: (context, idx) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${idx + 1}',
                                style: HarnessType.codeSm.copyWith(
                                  color: colors.textSecondary,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: HarnessSpace.md),
                            Expanded(
                              child: Text(
                                linesList[idx],
                                style: HarnessType.codeSm.copyWith(
                                  fontSize: 12,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 2: INSTALLED SKILLS
  // ==========================================

  Widget _buildInstalledSkillsTab(ThemeData theme) {
    final colors = HarnessColors.of(context);
    if (_installedSkills.isEmpty) {
      return _buildEmptySkillsView(theme);
    }

    return ListView(
      padding: const EdgeInsets.all(HarnessSpace.lg),
      children: [
        // Informational banner
        Container(
          padding: const EdgeInsets.all(HarnessSpace.md),
          decoration: BoxDecoration(
            color: colors.info.c100,
            borderRadius: HarnessRadius.smAll,
            border: Border.all(color: colors.info.c300),
          ),
          child: Row(
            children: [
              Icon(HarnessIcons.info, size: HarnessSize.iconMd, color: colors.info.c700),
              const SizedBox(width: HarnessSpace.md),
              Expanded(
                child: Text(
                  'Skills provide on-demand specialized workflows and reference files loaded transiently during active tasks.',
                  style: HarnessType.bodySm.copyWith(color: colors.info.c900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HarnessSpace.lg),
        ..._installedSkills.map((pkg) => _buildSkillCard(pkg, theme)),
        ..._buildMissingBuiltinCards(theme),
      ],
    );
  }

  /// Shows restore cards for bundled skills that are not installed.
  List<Widget> _buildMissingBuiltinCards(ThemeData theme) {
    final installed = _installedSkills
        .map((pkg) => pkg.directoryName)
        .toSet();
    final missing = kBuiltinSkills
        .where((definition) => !installed.contains(definition.name))
        .toList();
    if (missing.isEmpty) return const [];

    return [
      const SizedBox(height: HarnessSpace.sm),
      Text(
        'Built-in skills',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: HarnessSpace.sm),
      ...missing.map(
        (definition) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(HarnessIcons.lock),
            title: Text(definition.name),
            subtitle: const Text('Bundled skill is not installed'),
            trailing: IconButton(
              icon: const Icon(HarnessIcons.restore),
              tooltip: 'Restore built-in skill',
              onPressed: () => _restoreBuiltinSkill(definition.name),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildSkillCard(InstalledSkillPackage pkg, ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.mdAll,
        side: BorderSide(
          color: pkg.isMalformed ? colors.warning.c500 : colors.border,
          width: pkg.isMalformed ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showSkillDetailSheet(pkg),
        child: Padding(
          padding: const EdgeInsets.all(HarnessSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    HarnessIcons.skill,
                    size: HarnessSize.iconMd,
                    color: pkg.isMalformed
                        ? colors.warning.c700
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: HarnessSpace.sm),
                  Expanded(
                    child: Text(
                      pkg.displayName,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (pkg.isLocked) ...[
                    Icon(
                      HarnessIcons.lock,
                      size: HarnessSize.iconSm,
                      color: colors.textSecondary,
                    ),
                    IconButton(
                      icon: const Icon(
                        HarnessIcons.restore,
                        size: HarnessSize.iconSm,
                      ),
                      tooltip: 'Restore built-in skill',
                      onPressed: () => _restoreBuiltinSkill(pkg.directoryName),
                    ),
                  ],
                  if (pkg.isMalformed)
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(
                        horizontal: HarnessSpace.sm,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.warning.c100,
                        borderRadius: BorderRadius.circular(HarnessRadius.xs),
                        border: Border.all(color: colors.warning.c300),
                      ),
                      child: Text(
                        'Missing SKILL.md',
                        style: HarnessType.label.copyWith(
                          color: colors.warning.c900,
                        ),
                      ),
                    )
                  else
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
                        'v${pkg.version}',
                        style: HarnessType.label.copyWith(
                          color: colors.primary.c900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: HarnessSpace.sm),
              Text(
                pkg.description,
                style: HarnessType.bodySm.copyWith(
                  color: pkg.isMalformed
                      ? colors.warning.c900
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(height: HarnessSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        HarnessIcons.attachment,
                        size: HarnessSize.iconSm,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: HarnessSpace.xs),
                      Text(
                        '${pkg.subFileCount} auxiliary file${pkg.subFileCount == 1 ? '' : 's'}',
                        style: HarnessType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'View details',
                        style: HarnessType.label.copyWith(
                          color: colors.primary.c500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        HarnessIcons.chevronRight,
                        size: HarnessSize.iconSm,
                        color: colors.primary.c500,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySkillsView(ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HarnessMark(size: 48, accented: true),
            const SizedBox(height: HarnessSpace.lg),
            Text(
              'No skills installed',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: HarnessSpace.sm),
            Text(
              'Place skill directories containing a SKILL.md inside <HarnessRoot>/skills/ to make them available to the agent.',
              style: HarnessType.bodySm.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showSkillDetailSheet(InstalledSkillPackage pkg) {
    final colors = HarnessColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final sheetHeight = MediaQuery.of(bottomSheetContext).size.height * 0.85;

        return SizedBox(
          height: sheetHeight,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(HarnessSpace.lg, HarnessSpace.lg, HarnessSpace.sm, HarnessSpace.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkg.displayName,
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(
                              'skills/${pkg.directoryName}/',
                              style: HarnessType.codeSm.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(HarnessIcons.x),
                        onPressed: () => Navigator.pop(bottomSheetContext),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(HarnessSpace.lg),
                    children: [
                      if (pkg.isMalformed) ...[
                        Container(
                          padding: const EdgeInsets.all(HarnessSpace.md),
                          decoration: BoxDecoration(
                            color: colors.warning.c100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.warning.c300),
                          ),
                          child: Row(
                            children: [
                              Icon(HarnessIcons.warning, size: HarnessSize.iconSm, color: colors.warning.c700),
                              const SizedBox(width: HarnessSpace.sm),
                              Expanded(
                                child: Text(
                                  pkg.malformedReason ??
                                      'Package is malformed and cannot be loaded.',
                                  style: HarnessType.bodySm.copyWith(color: colors.warning.c900, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: HarnessSpace.lg),
                      ],
                      Text(
                        'SKILL.md Instructions',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: HarnessSpace.sm),
                      Container(
                        padding: const EdgeInsets.all(HarnessSpace.md),
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          borderRadius: HarnessRadius.smAll,
                          border: Border.all(color: colors.border),
                        ),
                        child: pkg.skillMdContent != null
                            ? MarkdownBody(
                                data: pkg.skillMdContent!,
                              )
                            : const Text('(No SKILL.md file present)'),
                      ),
                      if (pkg.auxiliaryFiles.isNotEmpty) ...[
                        const SizedBox(height: HarnessSpace.xl),
                        Text(
                          'Auxiliary Files (${pkg.auxiliaryFiles.length})',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: HarnessSpace.sm),
                        ...pkg.auxiliaryFiles.map(
                          (aux) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(HarnessIcons.file, size: HarnessSize.iconSm),
                            title: Text(aux, style: HarnessType.codeSm.copyWith(color: colors.textSecondary)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.md':
      case '.txt':
        return HarnessIcons.fileText;
      case '.json':
      case '.yaml':
      case '.yml':
        return HarnessIcons.fileJson;
      case '.dart':
      case '.py':
      case '.js':
      case '.sh':
        return HarnessIcons.fileCode;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.svg':
        return HarnessIcons.image;
      case '.pdf':
        return HarnessIcons.fileText;
      default:
        return HarnessIcons.file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Helper data class representing an entry in the storage workspace file tree.
class WorkspaceFileEntry {
  final String name;
  final String virtualPath;
  final String physicalPath;
  final bool isDirectory;
  final int sizeBytes;

  const WorkspaceFileEntry({
    required this.name,
    required this.virtualPath,
    required this.physicalPath,
    required this.isDirectory,
    this.sizeBytes = 0,
  });
}

/// User choice when an imported skill name already exists.
enum _SkillConflictChoice { overwrite, rename }

