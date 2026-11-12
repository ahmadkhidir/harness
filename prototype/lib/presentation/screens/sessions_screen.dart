import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/models/session.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/database/app_database.dart';
import '../../data/services/session_service.dart';
import '../bloc/harness_session_bloc.dart';
import '../bloc/harness_session_event.dart';
import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Screen 2: Sessions Management.
///
/// Route: `/sessions`
/// Implements the UI specification defined in `docs/Harness/screens/02-sessions.md`:
/// - Chronological list of session cards ordered by `updatedAt` descending.
/// - Displays session title, last active timestamp, turn metrics, context file size in KB,
///   and compaction indicator badge.
/// - Allows switching active session, creating new session via FAB (+), renaming sessions,
///   and deleting sessions with confirmation dialog.
class SessionsScreen extends StatefulWidget {
  final SessionService? sessionService;
  final AppDatabase? database;

  const SessionsScreen({
    super.key,
    this.sessionService,
    this.database,
  });

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final SessionService _sessionService;
  late final AppDatabase _database;

  bool _isLoading = true;
  String? _errorMessage;
  List<Session> _sessions = [];
  String? _activeSessionId;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase();
    _sessionService = widget.sessionService ??
        SessionService(
          database: _database,
          fileSystem: HarnessFileSystem.instance,
        );
    _loadSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final activeId = await _sessionService.getActiveSessionId();
      final sessions = await _sessionService.getAllSessions();

      if (mounted) {
        setState(() {
          _activeSessionId = activeId;
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sessions: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Session> get _filteredSessions {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _sessions;
    return _sessions.where((s) {
      return s.title.toLowerCase().contains(query) ||
          s.id.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _selectSession(Session session) async {
    await _sessionService.setActiveSessionId(session.id);
    if (!mounted) return;
    context.read<HarnessSessionBloc>().add(SwitchSessionEvent(session.id));
    Navigator.pop(context);
  }

  Future<void> _createNewSession() async {
    try {
      final session = await _sessionService.createSession(title: 'New Session');
      if (!mounted) return;
      context.read<HarnessSessionBloc>().add(SwitchSessionEvent(session.id));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create session: $e')),
        );
      }
    }
  }

  Future<void> _showRenameDialog(Session session) async {
    final controller = TextEditingController(text: session.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: 'Session title',
            hintText: 'Enter session title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != session.title) {
      try {
        await _sessionService.renameSession(session.id, newTitle);
        await _loadSessions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rename session: $e')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteDialog(Session session) async {
    final colors = HarnessColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: Icon(
          HarnessIcons.trash,
          color: colors.error.c500,
          size: 36,
        ),
        title: const Text('Delete session?'),
        content: Text(
          'Permanently delete "${session.title}" and its context files from disk?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error.c700,
              foregroundColor: colors.error.c100,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _sessionService.deleteSession(session.id);
        final newActiveId = await _sessionService.getActiveSessionId();
        if (mounted && newActiveId != null && newActiveId != session.id) {
          context.read<HarnessSessionBloc>().add(SwitchSessionEvent(newActiveId));
        }
        await _loadSessions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete session: $e')),
          );
        }
      }
    }
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1 && local.day == now.day) {
      return DateFormat('h:mm a').format(local);
    } else if (difference.inDays < 7) {
      return DateFormat('E, h:mm a').format(local);
    } else {
      return DateFormat('MMM d, yyyy').format(local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
        icon: const Icon(HarnessIcons.arrowLeft),
        tooltip: 'Back',
        onPressed: () => Navigator.maybePop(context),
      ),
      title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: theme.textTheme.titleLarge,
                decoration: InputDecoration(
                  hintText: 'Search sessions…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: theme.textTheme.titleLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Sessions'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(HarnessIcons.x),
              tooltip: 'Clear search',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _isSearching = false;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(HarnessIcons.search),
              tooltip: 'Search sessions',
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
        ],
      ),
      body: _buildBody(theme, colors),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New session',
        onPressed: _createNewSession,
        child: const Icon(HarnessIcons.add),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, HarnessColors colors) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HarnessSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HarnessIcons.error,
                size: 48,
                color: colors.error.c500,
              ),
              const SizedBox(height: HarnessSpace.lg),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: HarnessType.bodySm.copyWith(color: colors.error.c700),
              ),
              const SizedBox(height: HarnessSpace.lg),
              FilledButton.icon(
                icon: const Icon(HarnessIcons.refresh),
                label: const Text('Retry'),
                onPressed: _loadSessions,
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredSessions;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HarnessSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HarnessMark(size: 48, accented: true),
              const SizedBox(height: HarnessSpace.lg),
              Text(
                _isSearching ? 'No matching sessions' : 'No sessions yet',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: HarnessSpace.sm),
              Text(
                _isSearching
                    ? 'No session title or ID matches that search.'
                    : 'Start a session to keep turns, tool calls, and context together.',
                textAlign: TextAlign.center,
                style: HarnessType.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (!_isSearching) ...[
                const SizedBox(height: HarnessSpace.xl),
                FilledButton.icon(
                  icon: const Icon(HarnessIcons.newSession),
                  label: const Text('New session'),
                  onPressed: _createNewSession,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          HarnessSpace.lg,
          HarnessSpace.md,
          HarnessSpace.lg,
          HarnessSpace.xxxl + HarnessSpace.xl,
        ),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: HarnessSpace.md),
        itemBuilder: (context, index) {
          final session = filtered[index];
          final isActive = session.id == _activeSessionId;
          return _buildSessionCard(context, session, isActive, theme, colors);
        },
      ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    Session session,
    bool isActive,
    ThemeData theme,
    HarnessColors colors,
  ) {
    final contextSizeKb = (session.contextSizeBytes / 1024).toStringAsFixed(1);

    return Material(
      color: isActive ? colors.primary.c100 : colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.mdAll,
        side: BorderSide(
          color: isActive ? colors.primary.c500 : colors.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _selectSession(session),
        child: Padding(
          padding: const EdgeInsets.all(HarnessSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                session.title,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: HarnessSpace.sm),
                              Container(
                                height: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: HarnessSpace.sm,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colors.primary.c600,
                                  borderRadius:
                                      BorderRadius.circular(HarnessRadius.xs),
                                ),
                                child: Text(
                                  'Active',
                                  style: HarnessType.label.copyWith(
                                    color: colors.primary.c100,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: HarnessSpace.xs),
                        Text(
                          'Updated ${_formatTimestamp(session.updatedAt)}',
                          style: HarnessType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      HarnessIcons.more,
                      size: HarnessSize.iconMd,
                    ),
                    tooltip: 'Session options',
                    onSelected: (action) {
                      if (action == 'rename') {
                        _showRenameDialog(session);
                      } else if (action == 'delete') {
                        _showDeleteDialog(session);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(HarnessIcons.pencil, size: HarnessSize.iconSm),
                            SizedBox(width: HarnessSpace.sm),
                            Text('Rename'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              HarnessIcons.trash,
                              size: HarnessSize.iconSm,
                              color: colors.error.c500,
                            ),
                            const SizedBox(width: HarnessSpace.sm),
                            Text(
                              'Delete',
                              style: TextStyle(color: colors.error.c700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: HarnessSpace.md),
              Wrap(
                spacing: HarnessSpace.sm,
                runSpacing: HarnessSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MetaTag(
                    label:
                        '${session.totalTurns} ${session.totalTurns == 1 ? 'turn' : 'turns'}',
                    colors: colors,
                  ),
                  _MetaTag(
                    label: '$contextSizeKb KB context',
                    colors: colors,
                  ),
                  if (session.compactionCount > 0)
                    Container(
                      height: HarnessSize.pill - 4,
                      padding: const EdgeInsets.symmetric(
                        horizontal: HarnessSpace.sm,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warning.c100,
                        border: Border.all(color: colors.warning.c300),
                        borderRadius: BorderRadius.circular(HarnessRadius.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            HarnessIcons.compaction,
                            size: 12,
                            color: colors.warning.c700,
                          ),
                          const SizedBox(width: HarnessSpace.xs),
                          Text(
                            'Compacted ${session.compactionCount}×',
                            style: HarnessType.label.copyWith(
                              color: colors.warning.c700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small neutral metadata tag used for turn counts and context size.
class _MetaTag extends StatelessWidget {
  final String label;
  final HarnessColors colors;

  const _MetaTag({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: HarnessSize.pill - 4,
      padding: const EdgeInsets.symmetric(horizontal: HarnessSpace.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(HarnessRadius.xs),
      ),
      child: Text(
        label,
        style: HarnessType.label.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
