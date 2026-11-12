import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/on_device_model_spec.dart';
import '../../core/models/provider_config.dart';
import '../../core/models/turn.dart';
import '../../core/routes/app_routes.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/services/model_download_service.dart';
import '../../data/services/skills_service.dart';
import '../../data/services/timer_service.dart';
import '../bloc/harness_session_bloc.dart';
import '../bloc/harness_session_event.dart';
import '../bloc/harness_session_state.dart';
import '../bloc/model_switcher_bloc.dart';
import '../bloc/model_switcher_event.dart';
import '../bloc/model_switcher_state.dart';
import '../theme/brand_mark.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';
import '../utils/composer_tags.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/skill_picker_sheet.dart';
import '../widgets/storage_picker_sheet.dart';
import '../widgets/system_call_pill.dart';
import '../widgets/timer_strip.dart';
import '../widgets/tool_calls_bottom_sheet.dart';

/// Maps each live `surfaceId` to the index of the turn that anchors it.
///
/// An A2UI surface is a single object keyed by ID. The first turn that
/// introduces a `surfaceId` is its permanent slot in the chat stream; every
/// later `updateComponents` / `updateDataModel` delivery for that ID mutates
/// the surface in that same slot instead of adding another chat item. A later
/// `createSurface` for the same ID (after a delete) moves the anchor to the
/// re-creation turn.
Map<String, int> _surfaceAnchorTurnIndices(List<Turn> turns) {
  final anchors = <String, int>{};
  for (var index = 0; index < turns.length; index++) {
    final turn = turns[index];
    final surfaceId = turn.a2uiSurfaceId;
    if (surfaceId == null) continue;

    // A createSurface starts a new surface lifecycle, so it re-anchors even if
    // the same ID was used earlier. Updates keep the original anchor.
    final createsSurface = _turnCreatesSurface(turn, surfaceId);
    if (createsSurface || !anchors.containsKey(surfaceId)) {
      anchors[surfaceId] = index;
    }
  }
  return anchors;
}

/// True when [turn]'s recorded A2UI payload contains a `createSurface` for
/// [surfaceId].
bool _turnCreatesSurface(Turn turn, String surfaceId) {
  final messages = turn.a2uiPayload?['messages'];
  if (messages is! List) return false;
  for (final message in messages) {
    if (message is! Map) continue;
    final create = message['createSurface'];
    if (create is Map && create['surfaceId']?.toString() == surfaceId) {
      return true;
    }
  }
  return false;
}

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
  final SkillsService _skillsService = SkillsService();

  String _previousInput = '';
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    final sessionBloc = context.read<HarnessSessionBloc>();
    if (sessionBloc.state is HarnessSessionInitial) {
      sessionBloc.add(const InitializeSessionEvent());
    }
    _inputController.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_handleInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// Opens skill/file pickers when the user types `/` or `@`.
  void _handleInputChanged() {
    final previous = _previousInput;
    final next = _inputController.text;
    _previousInput = next;

    if (_pickerOpen) return;

    if (shouldOpenSkillPicker(previous, next)) {
      _openSkillPicker();
      return;
    }

    final cursor = _inputController.selection.baseOffset;
    final trigger = fileTriggerIndex(previous, next, cursor);
    if (trigger != null) {
      _openStoragePicker(trigger, cursor);
    }
  }

  Future<void> _openSkillPicker() async {
    _pickerOpen = true;
    final skills = _skillsService.scanAvailableSkills();
    final selected = await showSkillPickerSheet(context, skills);
    _pickerOpen = false;
    if (!mounted) return;

    if (selected != null) {
      _setInputText(insertSkillTag(selected.name));
    } else {
      _previousInput = _inputController.text;
    }
    _inputFocusNode.requestFocus();
  }

  Future<void> _openStoragePicker(int triggerIndex, int cursor) async {
    final fileSystem = HarnessFileSystem.instance;
    if (fileSystem == null) return;

    _pickerOpen = true;
    final path = await showStoragePickerSheet(context, fileSystem);
    _pickerOpen = false;
    if (!mounted) return;

    if (path != null) {
      final updated = insertFileTag(
        text: _inputController.text,
        triggerIndex: triggerIndex,
        cursor: cursor,
        path: path,
      );
      _setInputText(updated, cursor: triggerIndex + path.length + 2);
    } else {
      _previousInput = _inputController.text;
    }
    _inputFocusNode.requestFocus();
  }

  /// Replaces composer text without re-triggering the picker listeners.
  void _setInputText(String text, {int? cursor}) {
    _previousInput = text;
    final offset = (cursor ?? text.length).clamp(0, text.length);
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
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
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final colors = HarnessColors.of(bottomSheetContext);
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
                      style: theme.textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(HarnessIcons.settings),
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
                            ? HarnessIcons.radioSelected
                            : HarnessIcons.radioUnselected,
                        color: isActive
                            ? colors.primary.c500
                            : colors.textSecondary,
                      ),
                      title: Text(
                        config.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isActive ? colors.primary.c500 : null,
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
                            ' · $statusText',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isReady
                                  ? colors.success.c700
                                  : colors.error.c700,
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
          icon: Icon(
            HarnessIcons.keyMissing,
            color: HarnessColors.of(dialogCtx).warning.c700,
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
              icon: const Icon(HarnessIcons.settings, size: 18),
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
          icon: Icon(
            HarnessIcons.memory,
            color: HarnessColors.of(dialogCtx).error.c500,
            size: 36,
          ),
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
              icon: const Icon(HarnessIcons.switchModel, size: 18),
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
    final colors = HarnessColors.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(HarnessIcons.sessions),
          tooltip: 'Sessions',
          onPressed: () => Navigator.pushNamed(context, AppRoutes.sessions),
        ),
        title: BlocBuilder<ModelSwitcherBloc, ModelSwitcherState>(
          builder: (context, switcherState) {
            final colors = HarnessColors.of(context);
            final activeDisplayName = switcherState is ModelSwitcherLoaded
                ? switcherState.activeConfig.displayName
                : 'Loading model...';

            return InkWell(
              borderRadius: BorderRadius.circular(HarnessRadius.sm),
              onTap: () {
                if (switcherState is ModelSwitcherLoaded) {
                  _showModelQuickSelectSheet(context, switcherState);
                } else {
                  Navigator.pushNamed(context, AppRoutes.settings);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HarnessSpace.xs,
                  vertical: HarnessSpace.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HarnessMark(size: 20),
                    const SizedBox(width: HarnessSpace.sm - 2),
                    Flexible(
                      child: const HarnessWordmark(fontSize: 18),
                    ),
                    const SizedBox(width: HarnessSpace.sm),
                    Flexible(
                      child: Container(
                        height: HarnessSize.pill,
                        padding: const EdgeInsets.symmetric(
                          horizontal: HarnessSpace.sm,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.c100,
                          borderRadius: BorderRadius.circular(HarnessRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                activeDisplayName,
                                style: HarnessType.label.copyWith(
                                  color: colors.primary.c700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              HarnessIcons.chevronDown,
                              size: 14,
                              color: colors.primary.c700,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(HarnessIcons.more),
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'workspace') {
                Navigator.pushNamed(context, AppRoutes.workspace);
              } else if (value == 'settings') {
                Navigator.pushNamed(context, AppRoutes.settings);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'workspace',
                child: Row(
                  children: [
                    Icon(HarnessIcons.folder, size: HarnessSize.iconSm),
                    SizedBox(width: HarnessSpace.sm),
                    Flexible(child: Text('Workspace & Skills', overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(HarnessIcons.settings, size: HarnessSize.iconSm),
                    SizedBox(width: HarnessSpace.sm),
                    Flexible(child: Text('Settings', overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: BlocConsumer<HarnessSessionBloc, HarnessSessionState>(
        listener: (context, state) {
          if (state is HarnessSessionError) {
            _handleSessionError(context, state);
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
          final surfaceAnchors = _surfaceAnchorTurnIndices(turns);

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
                            final turn = turns[index];
                            final surfaceId = turn.a2uiSurfaceId;
                            final isSurfaceAnchor =
                                surfaceId != null &&
                                surfaceAnchors[surfaceId] == index;
                            return MessageBubble(
                              key: ValueKey(turn.id),
                              turn: turn,
                              a2uiSurface: isSurfaceAnchor
                                  ? sessionState.surfaces[surfaceId]
                                  : null,
                              isA2UISurfaceAnchor: isSurfaceAnchor,
                              isModelExecuting: isExecuting,
                              onA2UIAction: (componentId, action, dataModel) {
                                if (surfaceId == null) return;
                                context.read<HarnessSessionBloc>().add(
                                  HandleA2UIActionEvent(
                                    surfaceId: surfaceId,
                                    componentId: componentId,
                                    action: action,
                                    dataModel: dataModel,
                                  ),
                                );
                              },
                              onA2UIValueChanged: (path, value) {
                                if (surfaceId == null) return;
                                context.read<HarnessSessionBloc>().add(
                                  UpdateA2UISurfaceDataEvent(
                                    surfaceId: surfaceId,
                                    path: path,
                                    value: value,
                                  ),
                                );
                              },
                            );
                          }

                          // Live executing turn item
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HarnessSpace.lg,
                              vertical: HarnessSpace.sm,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.primary.c500,
                                  ),
                                ),
                                const SizedBox(width: HarnessSpace.sm),
                                Expanded(
                                  child: Text(
                                    executingState?.statusMessage ??
                                        'Thinking…',
                                    style: HarnessType.bodySm.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (executingState != null &&
                                    executingState.toolIndicators.isNotEmpty)
                                  IconButton(
                                    key: const ValueKey(
                                      'executing_tool_calls_button',
                                    ),
                                    icon: const Icon(
                                      HarnessIcons.chevronDown,
                                      size: HarnessSize.iconSm,
                                    ),
                                    tooltip:
                                        'Show tool calls (${executingState.toolIndicators.length})',
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
              if (sessionState.sessionId != null)
                TimerStrip(
                  sessionId: sessionState.sessionId!,
                  timerService: TimerService.instance,
                ),
              const Divider(height: 1),
              // Bottom pinned prompt input bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HarnessSpace.lg,
                    HarnessSpace.sm,
                    HarnessSpace.md,
                    HarnessSpace.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          style: HarnessType.body,
                          onSubmitted: (_) => _submitPrompt(),
                          decoration: InputDecoration(
                            hintText: isExecuting
                                ? 'Agent is working…'
                                : 'Ask Harness or give a task…',
                          ),
                        ),
                      ),
                      const SizedBox(width: HarnessSpace.sm),
                      SizedBox(
                        width: HarnessSize.button,
                        height: HarnessSize.button,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: isExecuting
                                ? colors.error.c700
                                : colors.primary.c600,
                            foregroundColor: isExecuting
                                ? colors.error.c100
                                : colors.primary.c100,
                            shape: const RoundedRectangleBorder(
                              borderRadius: HarnessRadius.smAll,
                            ),
                            minimumSize: const Size(
                              HarnessSize.button,
                              HarnessSize.button,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          icon: Icon(
                            isExecuting
                                ? HarnessIcons.stop
                                : HarnessIcons.send,
                          ),
                          tooltip:
                              isExecuting ? 'Stop Execution' : 'Send Prompt',
                          onPressed: isExecuting
                              ? _cancelActiveTurn
                              : () => _submitPrompt(),
                        ),
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
