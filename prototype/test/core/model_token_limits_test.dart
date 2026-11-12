import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/model_token_limits.dart';
import 'package:harness/core/models/on_device_model_spec.dart';
import 'package:harness/core/models/provider_config.dart';

void main() {
  group('Model token limits', () {
    test('remote providers use the large remote option list', () {
      final config = ProviderConfig(
        id: 'openai',
        providerType: 'openai',
        displayName: 'OpenAI',
        modelName: 'gpt-4o',
        maxOutputTokens: kDefaultRemoteMaxOutputTokens,
      );

      expect(resolveMaxOutputTokens(config), kDefaultRemoteMaxOutputTokens);
      final options = maxOutputTokenOptionsFor(config);
      expect(options, contains(16384));
      expect(options, contains(32768));
      expect(options, contains(65536));
      expect(options, contains(config.maxOutputTokens));
    });

    test('local providers are clamped to the selected model output cap', () {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
        maxOutputTokens: kDefaultRemoteMaxOutputTokens,
        extraConfig: const {
          'selectedModelSpecId': 'qwen_2_5_1_5b',
        },
      );

      expect(resolveMaxOutputTokens(config), 1024);
      expect(maxOutputTokenOptionsFor(config), [256, 512, 1024]);
      expect(localContextWindowTokensFor(config), 4096);
    });

    test('local lookup falls back to the model filename', () {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'Qwen3-0.6B.litertlm',
        maxOutputTokens: 2048,
      );

      final spec = findOnDeviceModelSpec(config);
      expect(spec, isNotNull);
      expect(spec!.id, 'qwen_3_0_6b');
      expect(resolveMaxOutputTokens(config), 1024);
    });

    test('local config cannot exceed the bundle context window', () {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'Qwen3-0.6B.litertlm',
        maxOutputTokens: 1024,
        extraConfig: const {
          'selectedModelSpecId': 'qwen_3_0_6b',
          'contextWindowTokens': 8192,
        },
      );

      expect(localContextWindowTokensFor(config), 4096);
    });

    test('unknown local models still receive a safe default cap', () {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'custom-model.bin',
        maxOutputTokens: 16384,
      );

      expect(resolveMaxOutputTokens(config), kDefaultLocalMaxOutputTokens);
      expect(maxOutputTokenOptionsFor(config), [256, 512, 1024]);
    });

    test('all bundled local specs declare conservative token budgets', () {
      for (final spec in kSupportedOnDeviceModels) {
        expect(spec.contextWindowTokens, greaterThanOrEqualTo(1024));
        expect(spec.maxOutputTokens, greaterThanOrEqualTo(256));
        expect(
          spec.maxOutputTokens,
          lessThan(spec.contextWindowTokens),
          reason: '${spec.name} must leave room for the prompt',
        );
      }
    });
  });
}
