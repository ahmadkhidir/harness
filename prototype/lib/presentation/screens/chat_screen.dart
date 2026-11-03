import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/models/on_device_model_spec.dart';
import '../../core/models/provider_config.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/model_download_service.dart';
import '../bloc/harness_session_bloc.dart';
import '../bloc/harness_session_event.dart';
import '../bloc/harness_session_state.dart';
import '../bloc/model_switcher_bloc.dart';
import '../bloc/model_switcher_event.dart';
import '../bloc/model_switcher_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/system_call_pill.dart';
import '../widgets/tool_calls_bottom_sheet.dart';

/// The primary interaction screen where users input tasks, monitor parallel tool runs,
/// and review agent responses.
///
/// Implements Screen 1 from `docs/Harness/screens/01-chat-session.md`:
/// - Renders scrollable conversational turn history.
/// - Displays real-time [SystemCallPill] badges in a live tool tray during multi-turn runs.
/// - Surfaces actionable authentication and memory boundary error dialogs directing to Settings.
/// - Connects to [HarnessSessionBloc] and [ModelSwitcherBloc].
class ChatScreen extends StatefulWidget {
  final ModelDownloadService? downloadService;

  const ChatScreen({super.key, this.downloadService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  late final ModelDownloadService _downloadService =
      widget.downloadService ?? ModelDownloadService();

  @override
  void initState() {
    super.initState();
    final sessionBloc = context.read<HarnessSessionBloc>();
    if (sessionBloc.state is HarnessSessionInitial) {
      sessionBloc.add(const InitializeSessionEvent());
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submitPrompt([String? explicitPrompt]) {
    final text = (explicitPrompt ?? _inputController.text).trim();
    if (text.isEmpty) return;

    _inputController.clear();
    context.read<HarnessSessionBloc>().add(SubmitUserPromptEvent(text));
    _scrollToBottom();
  }

  void _cancelActiveTurn() {
    context.read<HarnessSessionBloc>().add(const CancelActiveTurnEvent());
  }

  bool _isLocalModelDownloaded(ProviderConfig config) {
    if (config.providerType != 'local_device') return false;
    final modelName = config.modelName.trim();
    if (modelName.isEmpty || modelName == 'None') {
      return false;
    }

    final specId = config.extraConfig['selectedModelSpecId'] as String?;
    for (final spec in kSupportedOnDeviceModels) {
      if (spec.id == specId || spec.fileName == modelName) {
        if (_downloadService.isDownloaded(spec)) return true;
      }
    }

    final file = _downloadService.resolveModelFileSync(modelName);
    if (file != null && file.existsSync() && file.lengthSync() > 0) {
      return true;
    }

    final modelPath = config.extraConfig['modelPath'] as String?;
    if (modelPath != null && modelPath.isNotEmpty) {
      final directFile = File(modelPath);
      if (directFile.existsSync() && directFile.lengthSync() > 0) {
        return true;
      }
    }

    return false;
  }

  void _showModelQuickSelectSheet(
    BuildContext context,
    ModelSwitcherLoaded state,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Active Model',
                      style: Theme.of(bottomSheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Configure Keys',
                      onPressed: () {
                        Navigator.pop(bottomSheetContext);
                        Navigator.pushNamed(context, AppRoutes.settings);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: state.configs.length,
                  itemBuilder: (ctx, index) {
                    final config = state.configs[index];
                    final isActive = config.id == state.activeConfig.id;
                    final hasKey = state.hasKeyMap[config.id] ?? false;
                    final isLocal = config.providerType == 'local_device';
                    final isDownloaded =
                        isLocal && _isLocalModelDownloaded(config);
                    final isReady = isLocal ? isDownloaded : hasKey;
                    final statusText = isLocal
                        ? (isDownloaded ? 'Present' : 'Missing')
                        : (hasKey ? 'Key Configured' : 'Key Missing');

                    return ListTile(
                      leading: Icon(
                        isActive
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text(
                        config.displayName,
                        style: TextStyle(
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Flexible(
                            child: Text(
                              config.modelName,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ' • $statusText',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isReady
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        context.read<ModelSwitcherBloc>().add(
                          SelectActiveProviderEvent(config.id),
                        );
                        Navigator.pop(bottomSheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleSessionError(
    BuildContext context,
    HarnessSessionError errorState,
  ) {
    if (errorState.isAuthError) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: const Icon(
            Icons.key_off_rounded,
            color: Colors.amber,
            size: 36,
          ),
          title: const Text('Authentication Error'),
          content: Text(
            '${errorState.errorMessage}\n\nPlease configure or update your API credentials in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Dismiss'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Go to Settings'),
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.pushNamed(context, AppRoutes.settings);
              },
            ),
          ],
        ),
      );
    } else if (errorState.isMemoryError) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: const Icon(Icons.memory_rounded, color: Colors.red, size: 36),
          title: const Text('Memory Limit Exceeded'),
          content: Text(
            '${errorState.errorMessage}\n\nThe local on-device SLM exceeded mobile RAM boundaries. '
            'Switch to a cloud model or select a lighter architecture in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Dismiss'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.switch_access_shortcut_rounded, size: 18),
              label: const Text('Switch Model'),
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.pushNamed(context, AppRoutes.settings);
              },
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorState.errorMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.forum_outlined),
          tooltip: 'Sessions',
          onPressed: () => Navigator.pushNamed(context, AppRoutes.sessions),
        ),
        title: BlocBuilder<ModelSwitcherBloc, ModelSwitcherState>(
          builder: (context, switcherState) {
            final activeDisplayName = switcherState is ModelSwitcherLoaded
                ? switcherState.activeConfig.displayName
                : 'Loading model...';

            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (switcherState is ModelSwitcherLoaded) {
                  _showModelQuickSelectSheet(context, switcherState);
                } else {
                  Navigator.pushNamed(context, AppRoutes.settings);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Harness',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              activeDisplayName,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Workspace & Skills',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.workspace),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: BlocConsumer<HarnessSessionBloc, HarnessSessionState>(
        listener: (context, state) {
          if (state is HarnessSessionError) {
            _handleSessionError(context, state);
          } else if (state is HarnessA2UIActionResolved) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 3),
                backgroundColor:
                    state.isError ? Theme.of(context).colorScheme.error : null,
              ),
            );
            _scrollToBottom();
          } else if (state is HarnessTurnExecuting ||
              state is HarnessSessionReady) {
            _scrollToBottom();
          }
        },
        builder: (context, sessionState) {
          final turns = sessionState.turns;
          final executingState = sessionState is HarnessTurnExecuting
              ? sessionState
              : null;
          final isExecuting = executingState != null;

          return Column(
            children: [
              Expanded(
                child: turns.isEmpty && !isExecuting
                    ? EmptyState(
                        onSelectPrompt: (prompt) => _submitPrompt(prompt),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: turns.length + (isExecuting ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index < turns.length) {
                            return MessageBubble(
                              turn: turns[index],
                              onA2UIAction: (action, dataModel) {
                                context.read<HarnessSessionBloc>().add(
                                      HandleA2UIActionEvent(
                                        action: action,
                                        dataModel: dataModel,
                                      ),
                                    );
                              },
                            );
                          }

                          // Live executing turn item
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    executingState?.statusMessage ??
                                        'Thinking...',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: theme.colorScheme.outline,
                                        ),
                                  ),
                                ),
                                if (executingState != null &&
                                    executingState.toolIndicators.isNotEmpty)
                                  IconButton(
                                    key: const ValueKey(
                                      'executing_tool_calls_button',
                                    ),
                                    icon: const Icon(Icons.expand_more),
                                    tooltip:
                                        'Show tool calls (${executingState.toolIndicators.length})',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => showToolCallsBottomSheet(
                                      context,
                                      executingState.toolIndicators,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              // Bottom pinned prompt input bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitPrompt(),
                          decoration: InputDecoration(
                            hintText: isExecuting
                                ? 'Agent is working...'
                                : 'Ask Harness or give a task...',
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: Icon(
                          isExecuting
                              ? Icons.stop_circle_outlined
                              : Icons.arrow_upward_rounded,
                        ),
                        tooltip: isExecuting ? 'Stop Execution' : 'Send Prompt',
                        onPressed: isExecuting
                            ? _cancelActiveTurn
                            : () => _submitPrompt(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
