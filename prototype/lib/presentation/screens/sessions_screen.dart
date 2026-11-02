import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/models/session.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/database/app_database.dart';
import '../../data/services/session_service.dart';
import '../bloc/harness_session_bloc.dart';
import '../bloc/harness_session_event.dart';

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
          SnackBar(
            content: Text('Failed to create session: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showRenameDialog(Session session) async {
    final controller = TextEditingController(text: session.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: 'Session Title',
            hintText: 'Enter session title',
            border: OutlineInputBorder(),
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
            SnackBar(
              content: Text('Failed to rename session: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteDialog(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 36),
        title: const Text('Delete Session?'),
        content: Text(
          'Are you sure you want to permanently delete "${session.title}"?\n'
          'All message history and context files will be deleted from disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
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
            SnackBar(
              content: Text('Failed to delete session: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
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

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search sessions...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('All Sessions'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear Search',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _isSearching = false;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search Sessions',
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Session',
        onPressed: _createNewSession,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
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
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _isSearching ? 'No Matching Sessions' : 'No Sessions Yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isSearching
                    ? 'No sessions match your search criteria.'
                    : 'Start your first agent conversation thread to begin.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (!_isSearching)
                FilledButton.icon(
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Start First Session'),
                  onPressed: _createNewSession,
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final session = filtered[index];
          final isActive = session.id == _activeSessionId;
          return _buildSessionCard(context, session, isActive, theme);
        },
      ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    Session session,
    bool isActive,
    ThemeData theme,
  ) {
    final contextSizeKb = (session.contextSizeBytes / 1024).toStringAsFixed(1);

    return Card(
      elevation: isActive ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectSession(session),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? theme.colorScheme.primary : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Updated ${_formatTimestamp(session.updatedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
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
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Rename'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${session.totalTurns} ${session.totalTurns == 1 ? 'turn' : 'turns'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$contextSizeKb KB context',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (session.compactionCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        border: Border.all(color: Colors.purple.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: Colors.purple.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Compacted (${session.compactionCount}x)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade800,
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
