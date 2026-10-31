import 'package:http/http.dart' as http;
import '../core/models/provider_config.dart';
import 'claude_model_provider.dart';
import 'gemini_model_provider.dart';
import 'local_device_model_provider.dart';
import 'model_provider.dart';
import 'openai_compatible_provider.dart';
import 'openai_model_provider.dart';

/// Factory creating concrete [ModelProvider] adapters from [ProviderConfig] descriptors.
class ModelProviderFactory {
  /// Instantiates the appropriate adapter based on [config.providerType].
  static ModelProvider create({
    required ProviderConfig config,
    http.Client? client,
    OnDeviceInferenceEngine? onDeviceEngine,
  }) {
    switch (config.providerType) {
      case 'gemini':
        return GeminiModelProvider(config: config, client: client);
      case 'claude':
        return ClaudeModelProvider(config: config, client: client);
      case 'openai':
        return OpenAIModelProvider(config: config, client: client);
      case 'openai_compatible':
        return OpenAICompatibleProvider(config: config, client: client);
      case 'local_device':
        return LocalDeviceModelProvider(config: config, engine: onDeviceEngine);
      default:
        throw ArgumentError('Unsupported providerType: "${config.providerType}".');
    }
  }
}
