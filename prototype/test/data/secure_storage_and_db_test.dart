import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/provider_config.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/secure_storage/key_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late KeyStorageService keyStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_db_test_');
    db = AppDatabase.inMemory();
    await HarnessFileSystem.init(tempDir, db);
    keyStorage = KeyStorageService(useInMemoryFallback: true);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KeyStorageService Tests', () {
    test('saves, retrieves, checks presence, and deletes API keys', () async {
      expect(await keyStorage.hasApiKey('gemini'), isFalse);
      expect(await keyStorage.getApiKey('gemini'), isNull);

      await keyStorage.saveApiKey('gemini', 'sk-test-gemini-key');

      expect(await keyStorage.hasApiKey('gemini'), isTrue);
      expect(
        await keyStorage.getApiKey('gemini'),
        equals('sk-test-gemini-key'),
      );

      await keyStorage.deleteApiKey('gemini');

      expect(await keyStorage.hasApiKey('gemini'), isFalse);
      expect(await keyStorage.getApiKey('gemini'), isNull);
    });
  });

  group('AppDatabase Tests', () {
    test('seeds default provider configurations on creation', () async {
      final configs = await db.getAllProviderConfigs();
      expect(configs.length, equals(5));

      final active = await db.getActiveProviderConfig();
      expect(active, isNotNull);
      expect(active!.id, equals('gemini'));
      expect(active.providerType, equals('gemini'));
      expect(active.isActive, isTrue);
    });

    test('switches active provider atomically', () async {
      await db.setActiveProvider('claude');

      final active = await db.getActiveProviderConfig();
      expect(active, isNotNull);
      expect(active!.id, equals('claude'));
      expect(active.providerType, equals('claude'));

      final allConfigs = await db.getAllProviderConfigs();
      final gemini = allConfigs.firstWhere((c) => c.id == 'gemini');
      expect(gemini.isActive, isFalse);

      final claude = allConfigs.firstWhere((c) => c.id == 'claude');
      expect(claude.isActive, isTrue);
    });

    test('upserts provider configuration successfully', () async {
      final custom = ProviderConfig(
        id: 'custom_ollama',
        providerType: 'openai_compatible',
        displayName: 'Custom Ollama',
        modelName: 'mistral-7b',
        customEndpointUrl: 'http://192.168.1.50:11434/v1',
        temperature: 0.2,
      );

      await db.saveProviderConfig(custom);

      final allConfigs = await db.getAllProviderConfigs();
      expect(allConfigs.length, equals(6));

      final fetched = allConfigs.firstWhere((c) => c.id == 'custom_ollama');
      expect(fetched.displayName, equals('Custom Ollama'));
      expect(fetched.customEndpointUrl, equals('http://192.168.1.50:11434/v1'));
      expect(fetched.temperature, closeTo(0.2, 0.001));
    });

    test('stores and retrieves app settings', () async {
      expect(await db.getSetting('theme_mode'), isNull);

      await db.setSetting('theme_mode', 'dark');
      expect(await db.getSetting('theme_mode'), equals('dark'));

      await db.setSetting('theme_mode', 'light');
      expect(await db.getSetting('theme_mode'), equals('light'));
    });

    test('stores, retrieves, and updates root filesystem path and external mounts', () async {
      expect(await db.getRootPath(), isNull);

      await db.setRootPath('/storage/emulated/0/Documents/Harness');
      expect(await db.getRootPath(), equals('/storage/emulated/0/Documents/Harness'));

      final initialMounts = await db.getExternalMounts();
      expect(initialMounts.isEmpty, isTrue);

      await db.saveExternalMount('downloads', '/storage/emulated/0/Download');
      final updatedMounts = await db.getExternalMounts();
      expect(updatedMounts['downloads'], equals('/storage/emulated/0/Download'));

      await db.removeExternalMount('downloads');
      expect((await db.getExternalMounts()).containsKey('downloads'), isFalse);
    });
  });
}
