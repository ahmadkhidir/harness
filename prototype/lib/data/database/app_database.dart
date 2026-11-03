import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/models/provider_config.dart';

/// Persistent configuration and settings storage manager for Harness.
///
/// Backed entirely by [FlutterSecureStorage] (EncryptedSharedPreferences on Android,
/// Keychain on iOS). Supports an in-memory mode for offline widget and unit tests.
class AppDatabase {
  final FlutterSecureStorage? _storage;
  final bool _inMemory;
  final Map<String, String> _memoryStore;
  List<ProviderConfig>? _cachedConfigs;

  AppDatabase({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _inMemory = false,
      _memoryStore = {};

  /// In-memory constructor for unit and widget testing without native key-value isolate locks.
  AppDatabase.inMemory() : _storage = null, _inMemory = true, _memoryStore = {};

  static const String _configsKey = 'harness_provider_configs';
  static const String _rootPathKey = 'harness_root_path';
  static const String _externalMountsKey = 'harness_external_mounts';
  static const String _activeSessionIdKey = 'harness_active_session_id';
  static const String _searchProviderKey = 'harness_bridge_search_provider';
  static const String _runnerEndpointKey = 'harness_bridge_runner_endpoint';

  /// Search provider identifiers accepted by the external web bridge.
  static const Set<String> supportedSearchProviders = {
    'duckduckgo',
    'tavily',
    'brave',
  };

  static final List<ProviderConfig> _defaultConfigs = [
    ProviderConfig(
      id: 'gemini',
      providerType: 'gemini',
      displayName: 'Gemini',
      modelName: 'gemini-2.0-flash',
      isActive: true,
    ),
    ProviderConfig(
      id: 'claude',
      providerType: 'claude',
      displayName: 'Claude',
      modelName: 'claude-3-7-sonnet-20250219',
      isActive: false,
    ),
    ProviderConfig(
      id: 'openai',
      providerType: 'openai',
      displayName: 'OpenAI',
      modelName: 'gpt-4o',
      isActive: false,
    ),
    ProviderConfig(
      id: 'openai_compatible',
      providerType: 'openai_compatible',
      displayName: 'OpenAI-Compatible',
      modelName: 'llama3:8b',
      customEndpointUrl: 'http://localhost:11434/v1',
      isActive: false,
    ),
    ProviderConfig(
      id: 'local_device',
      providerType: 'local_device',
      displayName: 'On-Device SLM',
      modelName: 'None (Download required)',
      extraConfig: const {
        'selectedModelSpecId': '',
        'runtime': 'GGUF / LiteRT',
      },
      isActive: false,
    ),
  ];

  /// Reads a raw string value.
  Future<String?> _read(String key) async {
    if (_inMemory) return _memoryStore[key];
    try {
      return await _storage!.read(key: key) ?? _memoryStore[key];
    } catch (_) {
      return _memoryStore[key];
    }
  }

  /// Writes a raw string value.
  Future<void> _write(String key, String value) async {
    _memoryStore[key] = value;
    if (!_inMemory) {
      try {
        await _storage!.write(key: key, value: value);
      } catch (_) {}
    }
  }

  /// Retrieves the persisted root directory path chosen by the user, or null if not yet set.
  Future<String?> getRootPath() async {
    return await _read(_rootPathKey);
  }

  /// Persists the root directory path chosen by the user.
  Future<void> setRootPath(String path) async {
    await _write(_rootPathKey, path);
  }

  /// Retrieves all external workspace mounts as a tag -> directoryPath map.
  Future<Map<String, String>> getExternalMounts() async {
    final raw = await _read(_externalMountsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Adds or updates an external workspace mount tag.
  Future<void> saveExternalMount(String tag, String path) async {
    final mounts = await getExternalMounts();
    mounts[tag] = path;
    await _write(_externalMountsKey, json.encode(mounts));
  }

  /// Removes an external workspace mount tag.
  Future<void> removeExternalMount(String tag) async {
    final mounts = await getExternalMounts();
    mounts.remove(tag);
    await _write(_externalMountsKey, json.encode(mounts));
  }

  /// Retrieves the persisted active session ID, or null if none set.
  Future<String?> getActiveSessionId() async {
    return await _read(_activeSessionIdKey);
  }

  /// Persists the active session ID.
  Future<void> setActiveSessionId(String sessionId) async {
    await _write(_activeSessionIdKey, sessionId);
  }

  /// Retrieves the active web search provider identifier.
  ///
  /// Defaults to `duckduckgo`, which requires no API key, and ignores any
  /// persisted value that is no longer supported.
  Future<String> getSearchProviderId() async {
    final value = await _read(_searchProviderKey);
    if (value == null || !supportedSearchProviders.contains(value)) {
      return 'duckduckgo';
    }
    return value;
  }

  /// Persists the selected web search provider identifier.
  ///
  /// Throws [ArgumentError] when [id] is not a supported provider.
  Future<void> setSearchProviderId(String id) async {
    if (!supportedSearchProviders.contains(id)) {
      throw ArgumentError(
        'Unsupported search provider "$id". Expected one of $supportedSearchProviders.',
      );
    }
    await _write(_searchProviderKey, id);
  }

  /// Retrieves the configured external runner endpoint, or null when unset.
  Future<String?> getRunnerEndpoint() async {
    final value = await _read(_runnerEndpointKey);
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Persists the external runner endpoint; an empty value clears it.
  ///
  /// Throws [ArgumentError] when a non-empty value is not an absolute HTTP(S) URL.
  Future<void> setRunnerEndpoint(String? endpoint) async {
    final trimmed = endpoint?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _write(_runnerEndpointKey, '');
      return;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError(
        'Runner endpoint must be an absolute http(s) URL, got "$trimmed".',
      );
    }

    await _write(_runnerEndpointKey, trimmed);
  }

  /// Retrieves all configured model providers.
  Future<List<ProviderConfig>> getAllProviderConfigs() async {
    if (_cachedConfigs != null) return List.unmodifiable(_cachedConfigs!);

    final raw = await _read(_configsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (json.decode(raw) as List)
            .map(
              (item) => ProviderConfig.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        _cachedConfigs = list;
        return List.unmodifiable(list);
      } catch (_) {}
    }

    _cachedConfigs = List.from(_defaultConfigs);
    await _persistConfigs(_cachedConfigs!);
    return List.unmodifiable(_cachedConfigs!);
  }

  /// Retrieves the currently active provider configuration.
  Future<ProviderConfig?> getActiveProviderConfig() async {
    final configs = await getAllProviderConfigs();
    for (final c in configs) {
      if (c.isActive) return c;
    }
    return configs.isNotEmpty ? configs.first : null;
  }

  /// Sets the active provider by ID and unsets all others atomically.
  Future<void> setActiveProvider(String id) async {
    final configs = (await getAllProviderConfigs()).toList();
    var found = false;
    for (int i = 0; i < configs.length; i++) {
      final c = configs[i];
      if (c.id == id) {
        configs[i] = c.copyWith(isActive: true);
        found = true;
      } else {
        configs[i] = c.copyWith(isActive: false);
      }
    }
    if (!found) {
      throw ArgumentError('Provider config with ID "$id" does not exist.');
    }
    _cachedConfigs = configs;
    await _persistConfigs(configs);
  }

  /// Upserts a provider configuration.
  Future<void> saveProviderConfig(ProviderConfig config) async {
    final configs = (await getAllProviderConfigs()).toList();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configs[index] = config;
    } else {
      configs.add(config);
    }
    _cachedConfigs = configs;
    await _persistConfigs(configs);
  }

  Future<void> _persistConfigs(List<ProviderConfig> configs) async {
    final encoded = json.encode(configs.map((c) => c.toJson()).toList());
    await _write(_configsKey, encoded);
  }

  /// Retrieves an application setting value by key.
  Future<String?> getSetting(String key) async {
    return await _read('setting_$key');
  }

  /// Sets an application setting key-value pair.
  Future<void> setSetting(String key, String value) async {
    await _write('setting_$key', value);
  }

  /// Closes the storage manager (clears cached references).
  Future<void> close() async {
    _cachedConfigs = null;
  }
}
