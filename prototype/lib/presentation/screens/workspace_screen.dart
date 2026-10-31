import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import '../../core/models/installed_skill_package.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/services/skills_service.dart';

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
    _skillsService =
        widget.skillsService ?? SkillsService(fileSystem: _fs);
    _scanData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fileSearchController.dispose();
    super.dispose();
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
        title: const Text('Workspace & Skills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan Workspace',
            onPressed: _rescan,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.folder_outlined),
              text: 'Storage Files',
            ),
            Tab(
              icon: Icon(Icons.extension_outlined),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown error',
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _fileSearchController,
            decoration: InputDecoration(
              labelText: 'Search storage files',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _fileSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _fileSearchController.clear();
                          _fileSearchQuery = '';
                        });
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: Icon(
                        _getFileIcon(item.name),
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${item.virtualPath} • ${_formatFileSize(item.sizeBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _showFilePreviewSheet(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyStorageView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.folder_open_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _fileSearchQuery.isNotEmpty
                ? 'No matching files found'
                : 'No files in storage',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _fileSearchQuery.isNotEmpty
                ? 'Try a different search term.'
                : 'Files saved by the agent or placed in primary/ will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showFilePreviewSheet(WorkspaceFileEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              entry.virtualPath,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Copy Virtual Path',
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
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bottomSheetContext),
                      ),
                    ],
                  ),
                ),
                if (isTruncated)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Large file (> 2 MB): showing first 500 lines.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: linesList.length,
                      itemBuilder: (context, idx) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.outline,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                linesList[idx],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
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
    if (_installedSkills.isEmpty) {
      return _buildEmptySkillsView(theme);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Informational banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Skills provide on-demand specialized workflows and reference files loaded transiently during active tasks.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._installedSkills.map((pkg) => _buildSkillCard(pkg, theme)),
      ],
    );
  }

  Widget _buildSkillCard(InstalledSkillPackage pkg, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: pkg.isMalformed
              ? Colors.amber.shade700
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSkillDetailSheet(pkg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.extension,
                    size: 20,
                    color: pkg.isMalformed
                        ? Colors.amber.shade800
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pkg.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (pkg.isMalformed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Missing SKILL.md',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'v${pkg.version}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                pkg.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pkg.isMalformed
                      ? Colors.amber.shade900
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${pkg.subFileCount} auxiliary file${pkg.subFileCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'View details',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.primary,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
              child: Icon(
                Icons.extension_off_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No skills installed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Place skill directories containing a SKILL.md inside <HarnessRoot>/skills/ to make them available to the agent.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showSkillDetailSheet(InstalledSkillPackage pkg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkg.displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'skills/${pkg.directoryName}/',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bottomSheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (pkg.isMalformed) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pkg.malformedReason ??
                                      'Package is malformed and cannot be loaded.',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'SKILL.md Instructions',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: pkg.skillMdContent != null
                            ? MarkdownBody(
                                data: pkg.skillMdContent!,
                              )
                            : const Text('(No SKILL.md file present)'),
                      ),
                      if (pkg.auxiliaryFiles.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Auxiliary Files (${pkg.auxiliaryFiles.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...pkg.auxiliaryFiles.map(
                          (aux) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.insert_drive_file_outlined,
                                size: 18),
                            title: Text(
                              aux,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
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
        return Icons.description_outlined;
      case '.json':
      case '.yaml':
      case '.yml':
        return Icons.data_object;
      case '.dart':
      case '.py':
      case '.js':
      case '.sh':
        return Icons.code;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.svg':
        return Icons.image_outlined;
      case '.pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
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
