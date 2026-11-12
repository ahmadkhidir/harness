import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../core/models/model_token_limits.dart';
import '../../core/models/on_device_model_spec.dart';
import '../../core/models/provider_config.dart';
import '../../core/utils/file_system_manager.dart';
import '../../core/utils/network_guard.dart';
import '../../core/utils/storage_permission_service.dart';
import '../../data/database/app_database.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../data/services/model_download_service.dart';
import '../bloc/model_switcher_bloc.dart';
import '../bloc/model_switcher_event.dart';
import '../bloc/model_switcher_state.dart';
import '../theme/harness_colors.dart';
import '../theme/harness_icons.dart';
import '../theme/harness_tokens.dart';

/// Predefined recommended models for cloud and server providers to allow quick selection,
/// while still permitting any custom model identifier to be typed.
const Map<String, List<String>> kCloudProviderPresetModels = {
  'gemini': [
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.0-pro-exp-02-05',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ],
  'claude': [
    'claude-3-7-sonnet-20250219',
    'claude-3-5-sonnet-20241022',
    'claude-3-5-haiku-20241022',
    'claude-3-opus-20240229',
  ],
  'openai': ['gpt-4o', 'gpt-4o-mini', 'o1', 'o3-mini', 'gpt-4-turbo'],
  'openai_compatible': [
    'llama3:8b',
    'llama3.2:3b',
    'llama3.2:1b',
    'mistral:7b',
    'qwen2.5-coder:7b',
    'deepseek-r1:8b',
    'phi3:mini',
  ],
};

/// Settings and Model Switcher interface.
///
/// Implements FEAT-002: In-app interface for selecting the active provider,
/// choosing provider models dynamically, configuring parameters, and managing credentials.
class SettingsScreen extends StatefulWidget {
  final ModelDownloadService? downloadService;

  const SettingsScreen({super.key, this.downloadService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _selectedProviderId;
  String? _syncedProviderId;

  ModelDownloadService? _customDownloadService;
  ModelDownloadService get _downloadService =>
      widget.downloadService ??
      (_customDownloadService ??= ModelDownloadService());

  final Map<String, StreamSubscription<double>> _downloadSubscriptions = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingIds = {};

  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  double _temperature = 0.7;
  int _maxOutputTokens = kDefaultRemoteMaxOutputTokens;
  bool _obscureKey = true;

  String? _currentRootPath;
  Map<String, String> _externalMounts = {};

  String _searchProviderId = 'duckduckgo';
  final TextEditingController _tavilyKeyController = TextEditingController();
  final TextEditingController _braveKeyController = TextEditingController();
  final TextEditingController _runnerEndpointController =
      TextEditingController();
  final TextEditingController _allowedHostController = TextEditingController();
  List<String> _allowedHosts = [];
  bool _obscureBridgeKey = true;
  bool _hasTavilyKey = false;
  bool _hasBraveKey = false;

  @override
  void initState() {
    super.initState();
    context.read<ModelSwitcherBloc>().add(const LoadProviderConfigsEvent());
    _loadFilesystemSettings();
    _loadBridgeSettings();
  }

  /// Loads the persisted external bridge configuration (FEAT-008).
  Future<void> _loadBridgeSettings() async {
    final db = AppDatabase();
    final keyStorage = KeyStorageService();

    var providerId = 'duckduckgo';
    String? endpoint;
    var hasTavily = false;
    var hasBrave = false;
    var allowedHosts = <String>[];

    try {
      providerId = await db.getSearchProviderId();
      endpoint = await db.getRunnerEndpoint();
      allowedHosts = await db.getAllowedHosts();
      hasTavily = await keyStorage.hasApiKey('tavily');
      hasBrave = await keyStorage.hasApiKey('brave');
    } catch (_) {
      // Widget tests and unsupported hosts fall back to defaults.
    }

    if (!mounted) return;
    setState(() {
      _searchProviderId = providerId;
      _runnerEndpointController.text = endpoint ?? '';
      _allowedHosts = allowedHosts;
      _hasTavilyKey = hasTavily;
      _hasBraveKey = hasBrave;
    });
  }

  /// Adds a validated host to the pending `http_request` allowlist.
  void _addAllowedHost() {
    final entry = normalizeHostEntry(_allowedHostController.text);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a hostname or host:port (for example api.example.com).',
          ),
        ),
      );
      return;
    }

    setState(() {
      if (!_allowedHosts.contains(entry)) {
        _allowedHosts = [..._allowedHosts, entry]..sort();
      }
      _allowedHostController.clear();
    });
  }

  /// Removes a host from the pending `http_request` allowlist.
  void _removeAllowedHost(String host) {
    setState(() {
      _allowedHosts = _allowedHosts.where((entry) => entry != host).toList();
    });
  }

  /// Persists the external bridge configuration and any entered search keys.
  Future<void> _saveBridgeSettings() async {
    final db = AppDatabase();
    final keyStorage = KeyStorageService();

    try {
      await db.setSearchProviderId(_searchProviderId);
      await db.setRunnerEndpoint(_runnerEndpointController.text);
      await db.setAllowedHosts(_allowedHosts);

      final tavilyKey = _tavilyKeyController.text.trim();
      if (tavilyKey.isNotEmpty) {
        await keyStorage.saveApiKey('tavily', tavilyKey);
        _tavilyKeyController.clear();
      }

      final braveKey = _braveKeyController.text.trim();
      if (braveKey.isNotEmpty) {
        await keyStorage.saveApiKey('brave', braveKey);
        _braveKeyController.clear();
      }

      await _loadBridgeSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('External bridge settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save bridge settings: $e'),
        ),
      );
    }
  }

  void _loadFilesystemSettings() async {
    final db = AppDatabase();
    final root =
        await db.getRootPath() ?? HarnessFileSystem.instance?.rootDir.path;
    final mounts = await db.getExternalMounts();
    if (mounted) {
      setState(() {
        _currentRootPath = root;
        _externalMounts = mounts;
      });
    }
  }

  Future<void> _pickAndChangeRootFolder() async {
    try {
      if (Platform.isAndroid) {
        final hasPerm = await StoragePermissionService.hasPermission();
        if (!hasPerm) {
          await StoragePermissionService.requestPermission();
        }
      }

      final selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null || selectedDirectory.isEmpty) return;

      final harnessRoot = p.basename(selectedDirectory) == 'Harness'
          ? Directory(selectedDirectory)
          : Directory(p.join(selectedDirectory, 'Harness'));

      await harnessRoot.create(recursive: true);

      final db = AppDatabase();
      await db.setRootPath(harnessRoot.path);
      await HarnessFileSystem.init(harnessRoot, db);

      _customDownloadService = ModelDownloadService();
      _loadFilesystemSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Filesystem base updated to: ${harnessRoot.path}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not set folder: $e'),
          ),
        );
      }
    }
  }

  Future<void> _pickAndAddWorkspace() async {
    final colors = HarnessColors.of(context);
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null || selectedDirectory.isEmpty) return;

      final tagController = TextEditingController(
        text: p.basename(selectedDirectory).toLowerCase().replaceAll(' ', '_'),
      );

      if (!mounted) return;
      final tag = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Mount Workspace Tag'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Assign a virtual tag for the directory:\n$selectedDirectory\n\nThe model will access this directory as "<tag>/..."',
                  style: HarnessType.bodySm.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagController,
                  decoration: const InputDecoration(
                    labelText: 'Mount Tag (e.g. downloads, projects)',
                    
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final t = tagController.text.trim();
                  if (t.isNotEmpty && t != 'primary') {
                    Navigator.of(ctx).pop(t);
                  }
                },
                child: const Text('Mount'),
              ),
            ],
          );
        },
      );

      if (tag != null && tag.isNotEmpty) {
        final db = AppDatabase();
        await db.saveExternalMount(tag, selectedDirectory);
        HarnessFileSystem.instance?.mounts.registerMount(
          tag,
          Directory(selectedDirectory),
        );
        _loadFilesystemSettings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mounted "$tag/" -> $selectedDirectory')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not mount directory: $e'),
          ),
        );
      }
    }
  }

  Future<void> _removeWorkspace(String tag) async {
    try {
      final db = AppDatabase();
      await db.removeExternalMount(tag);
      HarnessFileSystem.instance?.mounts.unregisterMount(tag);
      _loadFilesystemSettings();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unmounted workspace "$tag/"')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not unmount: $e'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final sub in _downloadSubscriptions.values) {
      sub.cancel();
    }
    _modelController.dispose();
    _keyController.dispose();
    _urlController.dispose();
    _tavilyKeyController.dispose();
    _braveKeyController.dispose();
    _runnerEndpointController.dispose();
    _allowedHostController.dispose();
    super.dispose();
  }

  void _syncInputsForConfig(ProviderConfig config) {
    _modelController.text = config.modelName;
    _keyController.clear();
    _urlController.text = config.customEndpointUrl ?? '';
    _temperature = config.temperature;
    _maxOutputTokens = resolveMaxOutputTokens(config);
    _syncedProviderId = config.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarnessColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocConsumer<ModelSwitcherBloc, ModelSwitcherState>(
        listener: (context, state) {
          if (state is ModelSwitcherLoaded &&
              state.notificationMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.notificationMessage!)));
          } else if (state is ModelSwitcherFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage)),
            );
          }
        },
        builder: (context, state) {
          if (state is ModelSwitcherLoading || state is ModelSwitcherInitial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ModelSwitcherFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    HarnessIcons.error,
                    size: 48,
                    color: colors.error.c500,
                  ),
                  const SizedBox(height: HarnessSpace.md),
                  Text(
                    state.errorMessage,
                    style: HarnessType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: HarnessSpace.md),
                  FilledButton(
                    onPressed: () => context.read<ModelSwitcherBloc>().add(
                      const LoadProviderConfigsEvent(),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final loaded = state as ModelSwitcherLoaded;
          final configs = loaded.configs;

          final currentId = _selectedProviderId ?? loaded.activeConfig.id;
          final selectedConfig = configs.firstWhere(
            (c) => c.id == currentId,
            orElse: () => loaded.activeConfig,
          );

          if (_syncedProviderId != selectedConfig.id) {
            _selectedProviderId = selectedConfig.id;
            _syncInputsForConfig(selectedConfig);
          }

          final hasKey = loaded.hasKeyMap[selectedConfig.id] ?? false;
          final isOnDevice = selectedConfig.providerType == 'local_device';
          final presetModels =
              kCloudProviderPresetModels[selectedConfig.id] ??
              kCloudProviderPresetModels[selectedConfig.providerType] ??
              const [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Provider Dropdown Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Provider Selection',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedConfig.id),
                          decoration: const InputDecoration(
                            labelText: 'Select Provider',
                            
                            prefixIcon: Icon(HarnessIcons.provider),
                          ),
                          initialValue: selectedConfig.id,
                          items: configs.map((c) {
                            final isActive = c.id == loaded.activeConfig.id;
                            return DropdownMenuItem<String>(
                              value: c.id,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    c.displayName,
                                    style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: HarnessSpace.sm),
                                    Icon(
                                      HarnessIcons.check,
                                      size: HarnessSize.iconSm,
                                      color: colors.primary.c500,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (newId) {
                            if (newId != null && newId != selectedConfig.id) {
                              setState(() {
                                _selectedProviderId = newId;
                                final nextConfig = configs.firstWhere(
                                  (c) => c.id == newId,
                                  orElse: () => selectedConfig,
                                );
                                _syncInputsForConfig(nextConfig);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        if (selectedConfig.id != loaded.activeConfig.id)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              icon: const Icon(HarnessIcons.success),
                              label: Text(
                                'Set ${selectedConfig.displayName} as Active',
                              ),
                              onPressed: () {
                                context.read<ModelSwitcherBloc>().add(
                                  SelectActiveProviderEvent(selectedConfig.id),
                                );
                              },
                            ),
                          )
                        else
                          Row(
                            children: [
                              Icon(
                                HarnessIcons.success,
                                color: colors.success.c700,
                                size: HarnessSize.iconMd,
                              ),
                              const SizedBox(width: HarnessSpace.sm),
                              Text(
                                '${selectedConfig.displayName} is currently active',
                                style: HarnessType.bodySm.copyWith(
                                  color: colors.success.c700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Configuration Card for Selected Provider
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${selectedConfig.displayName} Configuration',
                          style: theme.textTheme.titleMedium,
                        ),
                        const Divider(height: 24),

                        // Render On-Device Model Manager OR Cloud Model Configuration
                        if (isOnDevice)
                          _buildOnDeviceModelManager(
                            config: selectedConfig,
                            theme: theme,
                          )
                        else
                          _buildCloudModelConfig(
                            context: context,
                            config: selectedConfig,
                            hasKey: hasKey,
                            presetModels: presetModels,
                            theme: theme,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildFilesystemCard(theme),
                const SizedBox(height: 16),
                _buildExternalBridgesCard(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilesystemCard(ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filesystem & Workspaces',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(HarnessIcons.refresh, size: 20),
                  onPressed: _loadFilesystemSettings,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Harness root storage and mounted workspace directories.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const Divider(height: 24),

            // 1. Primary User Root Path
            Text(
              'Filesystem',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.border.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.border.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentRootPath ??
                        (HarnessFileSystem.instance?.rootDir.path ??
                            'Default Documents'),
                    style: HarnessType.codeSm.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(HarnessIcons.folderOpen, size: 16),
              label: const Text('Change Folder'),
              onPressed: _pickAndChangeRootFolder,
            ),
            const SizedBox(height: 20),

            // 2. Mounted Workspaces
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mounted Workspaces',
                  style: theme.textTheme.titleSmall,
                ),
                TextButton.icon(
                  icon: const Icon(HarnessIcons.add, size: 16),
                  label: const Text('Add Workspace'),
                  onPressed: _pickAndAddWorkspace,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Locked Primary Workspace
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(HarnessIcons.lock, size: HarnessSize.iconMd),
              title: Text(
                'primary (default workspace)',
                style: HarnessType.bodySm.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                HarnessFileSystem.instance?.storageDir.path ?? 'storage/',
                style: HarnessType.codeSm.copyWith(color: colors.textSecondary),
              ),
            ),

            // Additional user mounts
            if (_externalMounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No additional external workspaces mounted.',
                  style: HarnessType.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              ..._externalMounts.entries.map((entry) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(HarnessIcons.folder, size: HarnessSize.iconMd),
                  title: Text(
                    entry.key,
                    style: HarnessType.bodySm.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    entry.value,
                    style: HarnessType.codeSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(HarnessIcons.trash, size: 18),
                    onPressed: () => _removeWorkspace(entry.key),
                    tooltip: 'Unmount workspace',
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Builds the On-Device Model Selection & Download Manager for LiteRT-LM runtime.
  Widget _buildOnDeviceModelManager({
    required ProviderConfig config,
    required ThemeData theme,
  }) {
    final colors = HarnessColors.of(context);
    final actualDownloadedIds = kSupportedOnDeviceModels
        .where((s) => _downloadService.isDownloaded(s))
        .map((s) => s.id)
        .toSet();

    final activeSpecId = config.extraConfig['selectedModelSpecId'] as String?;
    final activeSpec = findOnDeviceModelSpec(config);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'On-Device Model Selection',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Run AI directly on your device without an internet connection. Choose a model below to download and use offline.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (actualDownloadedIds.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.border.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  HarnessIcons.info,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No models downloaded. Choose and download a model below to use offline.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        ...kSupportedOnDeviceModels.map((spec) {
          final isDownloaded = actualDownloadedIds.contains(spec.id);
          final isDownloading = _downloadingIds.contains(spec.id);
          final progress = _downloadProgress[spec.id] ?? 0.0;
          final isSelected = isDownloaded && spec.id == activeSpecId;
          final hasPartial =
              !isDownloaded &&
              !isDownloading &&
              _downloadService.hasPartialDownload(spec);
          final partialBytes = hasPartial
              ? _downloadService.getPartialDownloadedBytes(spec)
              : 0;
          final partialProgress = hasPartial
              ? _downloadService.getPartialProgress(spec)
              : 0.0;

          final colors = HarnessColors.of(context);
          return Material(
            key: ValueKey('model_card_${spec.id}'),
            color: isSelected ? colors.primary.c100 : colors.surfaceSecondary,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: HarnessRadius.mdAll,
              side: BorderSide(
                color: isSelected ? colors.primary.c500 : colors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              onTap: () {
                if (isDownloaded) {
                  _selectOnDeviceModel(spec, config);
                } else if (!isDownloading) {
                  _startDownload(spec, config);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(HarnessSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSelected
                              ? HarnessIcons.radioSelected
                              : HarnessIcons.radioUnselected,
                          color: isSelected
                              ? colors.primary.c500
                              : colors.textSecondary,
                          size: HarnessSize.iconMd,
                        ),
                        const SizedBox(width: HarnessSpace.sm),
                        Expanded(
                          child: Text(
                            '${spec.name} (${spec.parameterSize})',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        // Tagged memory consumption badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: HarnessSpace.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: spec.memoryUsageMb > 2000
                                ? colors.warning.c100
                                : colors.success.c100,
                            borderRadius:
                                BorderRadius.circular(HarnessRadius.xs),
                            border: Border.all(
                              color: spec.memoryUsageMb > 2000
                                  ? colors.warning.c300
                                  : colors.success.c300,
                            ),
                          ),
                          child: Text(
                            spec.memoryTag,
                            style: HarnessType.label.copyWith(
                              color: spec.memoryUsageMb > 2000
                                  ? colors.warning.c900
                                  : colors.success.c900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HarnessSpace.xs + 2),
                    Text(
                      spec.description,
                      style: HarnessType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: HarnessSpace.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              HarnessIcons.memory,
                              size: 14,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Size: ${spec.downloadSize}',
                              style: HarnessType.label.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                        if (isDownloading)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(progress * 100).toInt()}% • ${(progress * spec.totalSizeInMb).toStringAsFixed(0)} / ${spec.downloadSize}',
                                style: HarnessType.label.copyWith(color: colors.primary.c500),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                key: ValueKey('pause_btn_${spec.id}'),
                                icon: const Icon(HarnessIcons.pause, size: 16),
                                tooltip: 'Pause download',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _pauseDownload(spec),
                              ),
                            ],
                          )
                        else if (hasPartial)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(partialProgress * 100).toInt()}% (${(partialBytes / (1024 * 1024)).toStringAsFixed(0)} MB)',
                                style: HarnessType.label.copyWith(color: colors.warning.c700),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                key: ValueKey('resume_btn_${spec.id}'),
                                icon: const Icon(HarnessIcons.resume, size: 16),
                                tooltip: 'Resume',
                                onPressed: () => _startDownload(spec, config),
                              ),
                              IconButton(
                                key: ValueKey('discard_btn_${spec.id}'),
                                icon: const Icon(HarnessIcons.x, size: 16),
                                tooltip: 'Discard partial download',
                                onPressed: () => _discardPartialDownload(spec),
                              ),
                            ],
                          )
                        else if (!isDownloaded)
                          TextButton.icon(
                            key: ValueKey('download_btn_${spec.id}'),
                            icon: const Icon(
                              HarnessIcons.download,
                              size: 16,
                            ),
                            label: const Text('Download'),
                            onPressed: () {
                              _startDownload(spec, config);
                            },
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                HarnessIcons.success,
                                size: 16,
                                color: colors.primary.c500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Downloaded',
                                style: HarnessType.label.copyWith(color: colors.success.c700),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                key: ValueKey('delete_model_${spec.id}'),
                                icon: const Icon(
                                  HarnessIcons.trash,
                                  size: 16,
                                ),
                                tooltip: 'Delete model weights',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _deleteModel(spec, config),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          minHeight: 4,
                        ),
                      ),
                    ] else if (hasPartial) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: partialProgress,
                          minHeight: 4,
                          backgroundColor:
                              colors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.warning.c500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        _buildParameterControls(
          theme,
          isLocal: true,
          localMaxOutputTokens: activeSpec?.maxOutputTokens,
        ),
      ],
    );
  }

  Future<void> _startDownload(
    OnDeviceModelSpec spec,
    ProviderConfig config,
  ) async {
    if (_downloadingIds.contains(spec.id)) return;

    if (Platform.isAndroid) {
      final hasPerm = await StoragePermissionService.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          final grant = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Storage Permission Required'),
              content: const Text(
                'To download models and save workspaces to your chosen storage location, '
                'please allow "All files access" for Harness in Android Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );

          if (grant == true) {
            await StoragePermissionService.requestPermission();
          }
        }
        return;
      }
    }

    setState(() {
      _downloadingIds.add(spec.id);
      _downloadProgress[spec.id] = _downloadService.getPartialProgress(spec);
    });

    final stream = _downloadService.downloadModel(spec);
    _downloadSubscriptions[spec.id] = stream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress[spec.id] = progress;
        });

        if (progress >= 1.0) {
          _downloadSubscriptions[spec.id]?.cancel();
          _downloadSubscriptions.remove(spec.id);

          setState(() {
            _downloadingIds.remove(spec.id);
            _downloadProgress.remove(spec.id);
          });

          // Automatically select the downloaded model
          _selectOnDeviceModel(spec, config);
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _downloadingIds.remove(spec.id);
          _downloadProgress.remove(spec.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download paused for ${spec.name}: $err'),
            action: SnackBarAction(
              label: 'Resume',
              onPressed: () => _startDownload(spec, config),
            ),
          ),
        );
      },
    );
  }

  void _pauseDownload(OnDeviceModelSpec spec) {
    _downloadSubscriptions[spec.id]?.cancel();
    _downloadSubscriptions.remove(spec.id);
    _downloadService.cancelDownload(spec.id);
    if (!mounted) return;
    setState(() {
      _downloadingIds.remove(spec.id);
      _downloadProgress.remove(spec.id);
    });
  }

  Future<void> _discardPartialDownload(OnDeviceModelSpec spec) async {
    _pauseDownload(spec);
    await _downloadService.cancelAndClearDownload(spec);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteModel(
    OnDeviceModelSpec spec,
    ProviderConfig config,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${spec.name}?'),
        content: Text(
          'This will remove ${spec.downloadSize} from your device storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _downloadService.deleteDownloadedModel(spec);
    if (!mounted) return;

    // If deleted model was active, clear selection
    if (config.extraConfig['selectedModelSpecId'] == spec.id) {
      final updated = config.copyWith(
        modelName: 'None',
        extraConfig: {
          ...config.extraConfig,
          'selectedModelSpecId': null,
          'modelPath': null,
        },
      );
      context.read<ModelSwitcherBloc>().add(
        UpdateProviderConfigEvent(updated),
      );
    }
    setState(() {});
  }

  Future<void> _selectOnDeviceModel(
    OnDeviceModelSpec spec,
    ProviderConfig currentConfig,
  ) async {
    final modelFile = await _downloadService.resolveModelFileAsync(
      spec.fileName.trim(),
    );

    final clampedMaxOutput =
        _maxOutputTokens.clamp(1, spec.maxOutputTokens);

    setState(() {
      _modelController.text = spec.fileName.trim();
      _maxOutputTokens = clampedMaxOutput;
    });

    final updated = currentConfig.copyWith(
      modelName: spec.fileName.trim(),
      extraConfig: {
        ...currentConfig.extraConfig,
        'selectedModelSpecId': spec.id,
        'simulatedAllocatedMb': spec.memoryUsageMb,
        'format': spec.format,
        'modelPath': modelFile.path.trim(),
        'contextWindowTokens': spec.contextWindowTokens,
      },
      temperature: _temperature,
      maxOutputTokens: clampedMaxOutput,
    );

    if (mounted) {
      context.read<ModelSwitcherBloc>().add(UpdateProviderConfigEvent(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${spec.name} selected (${spec.memoryTag}). Ready for LiteRT offline inference.',
          ),
        ),
      );
    }
  }

  /// Builds configuration inputs for cloud and server LLM providers.
  Widget _buildCloudModelConfig({
    required BuildContext context,
    required ProviderConfig config,
    required bool hasKey,
    required List<String> presetModels,
    required ThemeData theme,
  }) {
    final colors = HarnessColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section A: Model Selection
        Text(
          'Model Selection',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('${config.id}_${_modelController.text}'),
          decoration: const InputDecoration(
            labelText: 'Model Preset',
            
            prefixIcon: Icon(HarnessIcons.sliders),
          ),
          initialValue: presetModels.contains(_modelController.text)
              ? _modelController.text
              : 'custom',
          items: [
            ...presetModels.map(
              (m) => DropdownMenuItem(value: m, child: Text(m)),
            ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Custom Model...'),
            ),
          ],
          onChanged: (val) {
            if (val != null && val != 'custom') {
              setState(() {
                _modelController.text = val;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          decoration: const InputDecoration(
            labelText: 'Model Identifier',
            hintText: 'e.g. gemini-2.0-flash, gpt-4o, claude-3-7-sonnet',
            
            prefixIcon: Icon(HarnessIcons.model),
            helperText:
                'Select from presets above or enter a custom model name.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // Section B: API Credentials
        Text(
          'API Credentials',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyController,
          obscureText: _obscureKey,
          decoration: InputDecoration(
            labelText: 'API Key for ${config.displayName}',
            hintText: hasKey ? '••••••••••••••••' : 'Enter API Key',
            helperText: hasKey
                ? '✓ API key is saved in encrypted keystore'
                : 'No API key configured for ${config.displayName}',
            helperStyle: TextStyle(
              color: hasKey ? colors.success.c700 : colors.warning.c700,
            ),
            
            prefixIcon: const Icon(HarnessIcons.key),
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? HarnessIcons.keyHidden : HarnessIcons.keyVisible),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(HarnessIcons.save, size: 18),
              label: const Text('Save Key'),
              onPressed: () {
                final key = _keyController.text.trim();
                if (key.isNotEmpty) {
                  context.read<ModelSwitcherBloc>().add(
                    SaveApiKeyForProviderEvent(
                      providerId: config.id,
                      apiKey: key,
                    ),
                  );
                  _keyController.clear();
                }
              },
            ),
            if (hasKey) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(HarnessIcons.trash, size: 18),
                label: const Text('Delete Key'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error.c700,
                ),
                onPressed: () {
                  context.read<ModelSwitcherBloc>().add(
                    DeleteApiKeyForProviderEvent(config.id),
                  );
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Section C: Custom Endpoint URL
        if (config.providerType == 'openai_compatible' ||
            config.customEndpointUrl != null) ...[
          Text(
            'Custom Endpoint',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Endpoint URL',
              hintText: 'https://opencode.ai/zen/go/v1',
              helperText:
                  'Base URL for OpenAI-compatible endpoints such as OpenCode, Ollama, vLLM, LocalAI, or custom OpenAI proxies. OpenCode session headers are added automatically.',
              helperMaxLines: 3,
              
              prefixIcon: Icon(HarnessIcons.link),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Section D: Parameters
        _buildParameterControls(theme, isLocal: false),
        const SizedBox(height: 24),

        // Section E: Save Button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(HarnessIcons.save),
            label: Text('Save ${config.displayName} Settings'),
            onPressed: () {
              final newModel = _modelController.text.trim().isNotEmpty
                  ? _modelController.text.trim()
                  : config.modelName;
              final newUrl = _urlController.text.trim().isNotEmpty
                  ? _urlController.text.trim()
                  : null;

              final updated = config.copyWith(
                modelName: newModel,
                customEndpointUrl: newUrl,
                temperature: _temperature,
                maxOutputTokens: _maxOutputTokens,
              );

              context.read<ModelSwitcherBloc>().add(
                UpdateProviderConfigEvent(updated),
              );

              final enteredKey = _keyController.text.trim();
              if (enteredKey.isNotEmpty) {
                context.read<ModelSwitcherBloc>().add(
                  SaveApiKeyForProviderEvent(
                    providerId: config.id,
                    apiKey: enteredKey,
                  ),
                );
                _keyController.clear();
              }
            },
          ),
        ),
      ],
    );
  }

  /// External Bridges configuration card (FEAT-008).
  ///
  /// Configures the search provider, search credentials, and external runner
  /// endpoint used by the `web_search`, `web_fetch`, and `execute_script`
  /// commands.
  Widget _buildExternalBridgesCard(ThemeData theme) {
    final colors = HarnessColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'External Bridges',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(HarnessIcons.refresh, size: 20),
                  onPressed: _loadBridgeSettings,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Web search and script execution are delegated to external services.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const Divider(height: 24),
            Text(
              'Web Search',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('bridge_search_$_searchProviderId'),
              decoration: const InputDecoration(
                labelText: 'Search Provider',
                
                prefixIcon: Icon(HarnessIcons.searchProvider),
              ),
              initialValue: _searchProviderId,
              items: const [
                DropdownMenuItem(
                  value: 'duckduckgo',
                  child: Text('DuckDuckGo (no API key)'),
                ),
                DropdownMenuItem(value: 'tavily', child: Text('Tavily')),
                DropdownMenuItem(value: 'brave', child: Text('Brave')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _searchProviderId = value);
                }
              },
            ),
            if (_searchProviderId == 'tavily') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tavilyKeyController,
                obscureText: _obscureBridgeKey,
                decoration: InputDecoration(
                  labelText: 'Tavily API Key',
                  hintText: _hasTavilyKey ? '••••••••••••••••' : 'tvly-...',
                  helperText: _hasTavilyKey
                      ? '✓ Tavily key is saved in the encrypted keystore'
                      : 'A Tavily key is required for this provider',
                  helperStyle: TextStyle(
                    color: _hasTavilyKey
                        ? colors.success.c700
                        : colors.warning.c700,
                  ),
                  
                  prefixIcon: const Icon(HarnessIcons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureBridgeKey
                          ? HarnessIcons.keyHidden
                          : HarnessIcons.keyVisible,
                    ),
                    onPressed: () =>
                        setState(() => _obscureBridgeKey = !_obscureBridgeKey),
                  ),
                ),
              ),
            ],
            if (_searchProviderId == 'brave') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _braveKeyController,
                obscureText: _obscureBridgeKey,
                decoration: InputDecoration(
                  labelText: 'Brave API Key',
                  hintText: _hasBraveKey ? '••••••••••••••••' : 'BSA...',
                  helperText: _hasBraveKey
                      ? '✓ Brave key is saved in the encrypted keystore'
                      : 'A Brave subscription token is required for this provider',
                  helperStyle: TextStyle(
                    color: _hasBraveKey
                        ? colors.success.c700
                        : colors.warning.c700,
                  ),
                  
                  prefixIcon: const Icon(HarnessIcons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureBridgeKey
                          ? HarnessIcons.keyHidden
                          : HarnessIcons.keyVisible,
                    ),
                    onPressed: () =>
                        setState(() => _obscureBridgeKey = !_obscureBridgeKey),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'External Runner',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _runnerEndpointController,
              decoration: const InputDecoration(
                labelText: 'Runner Endpoint',
                hintText: 'https://runner.example.com',
                helperText:
                    'Base URL for external script execution (POST /execute). Leave empty to disable.',
                
                prefixIcon: Icon(HarnessIcons.runner),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Allowed Hosts',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Hosts approved for http_request. Downloads are not restricted by this list.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _allowedHostController,
                    decoration: const InputDecoration(
                      labelText: 'Add host',
                      hintText: 'api.example.com or api.example.com:8443',
                      
                      prefixIcon: Icon(HarnessIcons.publicHost),
                    ),
                    onSubmitted: (_) => _addAllowedHost(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(HarnessIcons.add),
                  tooltip: 'Add host',
                  onPressed: _addAllowedHost,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_allowedHosts.isEmpty)
              Text(
                'No hosts allowed. http_request is blocked until a host is added and saved.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.warning.c700,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _allowedHosts
                    .map(
                      (host) => InputChip(
                        label: Text(host),
                        onDeleted: () => _removeAllowedHost(host),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(HarnessIcons.save),
                label: const Text('Save External Bridges'),
                onPressed: _saveBridgeSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParameterControls(
    ThemeData theme, {
    required bool isLocal,
    int? localMaxOutputTokens,
  }) {
    final colors = HarnessColors.of(context);
    final localCap = localMaxOutputTokens ?? kDefaultLocalMaxOutputTokens;
    final List<int> options;
    if (isLocal) {
      options = kLocalMaxOutputTokenOptions
          .where((value) => value <= localCap)
          .toList();
      if (options.isEmpty) options.add(localCap);
      if (!options.contains(localCap)) options.add(localCap);
      options.sort();
    } else {
      options = <int>{
        ...kRemoteMaxOutputTokenOptions,
        // Keep a migrated or hand-edited value selectable rather than letting
        // the dropdown assert because its current value is not in the list.
        _maxOutputTokens,
      }.toList()
        ..sort();
    }

    final selected =
        options.contains(_maxOutputTokens) ? _maxOutputTokens : options.last;
    final helperText = isLocal
        ? 'On-device models are capped at ${_formatTokenCount(localCap)} output tokens.'
        : 'Remote models allow larger outputs. Provider/model caps still apply.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parameters',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Temperature'),
            Text(
              _temperature.toStringAsFixed(1),
              style: HarnessType.bodySm.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(
          value: _temperature,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          label: _temperature.toStringAsFixed(1),
          onChanged: (val) => setState(() => _temperature = val),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: ValueKey('tokens_${isLocal ? 'local' : 'remote'}_$selected'),
          decoration: InputDecoration(
            labelText: 'Max Output Tokens',
            helperText: helperText,
            helperMaxLines: 2,
            
            prefixIcon: const Icon(HarnessIcons.tokens),
          ),
          initialValue: selected,
          items: options
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text('${_formatTokenCount(value)} tokens'),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _maxOutputTokens = val);
          },
        ),
      ],
    );
  }

  /// Formats a token count with thousands separators for the settings labels.
  String _formatTokenCount(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }
}
