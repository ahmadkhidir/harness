import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure hardware-backed credential storage for API keys.
///
/// Uses Keychain on iOS and EncryptedSharedPreferences on Android via [FlutterSecureStorage].
/// Supports an in-memory dictionary fallback for offline unit tests.
class KeyStorageService {
  final FlutterSecureStorage? _storage;
  final Map<String, String>? _inMemoryFallback;

  KeyStorageService({
    FlutterSecureStorage? storage,
    bool useInMemoryFallback = false,
  })  : _storage = useInMemoryFallback ? null : (storage ?? const FlutterSecureStorage()),
        _inMemoryFallback = useInMemoryFallback ? <String, String>{} : null;

  /// Securely stores an API key for the specified provider.
  Future<void> saveApiKey(String providerId, String key) async {
    if (_inMemoryFallback != null) {
      _inMemoryFallback['key_$providerId'] = key;
      return;
    }
    await _storage!.write(key: 'key_$providerId', value: key);
  }

  /// Retrieves an encrypted API key for the specified provider, or null if unset.
  Future<String?> getApiKey(String providerId) async {
    if (_inMemoryFallback != null) {
      return _inMemoryFallback['key_$providerId'];
    }
    return await _storage!.read(key: 'key_$providerId');
  }

  /// Deletes an API key for the specified provider.
  Future<void> deleteApiKey(String providerId) async {
    if (_inMemoryFallback != null) {
      _inMemoryFallback.remove('key_$providerId');
      return;
    }
    await _storage!.delete(key: 'key_$providerId');
  }

  /// Checks if an API key is stored for the specified provider.
  Future<bool> hasApiKey(String providerId) async {
    final key = await getApiKey(providerId);
    return key != null && key.isNotEmpty;
  }
}
