/// Configuration record for an LLM model provider adapter.
///
/// Stored in the local relational database (`harness_app.db`) and used to instantiate
/// corresponding [ModelProvider] drivers.
/// Conforms to JSON Schema `https://harness.agent/schemas/provider-config.schema.json`.
class ProviderConfig {
  /// Allowed driver types recognized by the Harness runtime.
  static const validProviderTypes = {
    'gemini',
    'claude',
    'openai',
    'openai_compatible',
    'local_device',
  };

  /// Unique stable key for this configuration entry, e.g. `gemini` or `ollama`.
  final String id;

  /// Underlying adapter driver type: must be one of [validProviderTypes].
  final String providerType;

  /// User-facing label displayed in the settings model switcher (max 64 characters).
  final String displayName;

  /// Target model identifier passed to the inference API, e.g. `gemini-2.0-flash` or `claude-3-7-sonnet`.
  final String modelName;

  /// Base URL for OpenAI-compatible endpoints (Ollama, vLLM, DeepSeek, OpenCode).
  /// Null for official cloud providers that use hardcoded standard API base URLs.
  final String? customEndpointUrl;

  /// Sampling temperature for model generation (bounded between 0.0 and 2.0).
  final double temperature;

  /// Maximum tokens the model is permitted to generate per turn (minimum 1).
  final int maxOutputTokens;

  /// True if this configuration is currently the active model driver in Harness.
  final bool isActive;

  /// Key-value map of custom HTTP headers sent with each request (e.g. routing tokens, auth prefixes).
  final Map<String, String> customHeaders;

  /// Extensible key-value dictionary for provider-specific parameters
  /// (e.g. `thinkingBudgetTokens`, `contextWindowTokens`, `safetySettings`).
  final Map<String, dynamic> extraConfig;

  ProviderConfig({
    required this.id,
    required this.providerType,
    required this.displayName,
    required this.modelName,
    this.customEndpointUrl,
    this.temperature = 0.7,
    this.maxOutputTokens = 4096,
    this.isActive = false,
    this.customHeaders = const {},
    this.extraConfig = const {},
  }) {
    // Validate providerType against known supported adapters
    if (!validProviderTypes.contains(providerType)) {
      throw ArgumentError(
        'Invalid providerType "$providerType". Must be one of $validProviderTypes.',
      );
    }
    if (displayName.length > 64) {
      throw ArgumentError('displayName cannot exceed 64 characters.');
    }
    if (temperature < 0.0 || temperature > 2.0) {
      throw ArgumentError('temperature must be between 0.0 and 2.0.');
    }
    if (maxOutputTokens < 1) {
      throw ArgumentError('maxOutputTokens must be at least 1.');
    }

    // Verify customEndpointUrl conforms to URI format with scheme
    // (e.g. http://localhost:11434/v1) to prevent malformed HTTP requests at runtime.
    if (customEndpointUrl != null && customEndpointUrl!.isNotEmpty) {
      final uri = Uri.tryParse(customEndpointUrl!);
      if (uri == null || !uri.hasScheme) {
        throw ArgumentError(
          'customEndpointUrl must be a valid URI with a scheme.',
        );
      }
    }
  }

  /// Serializes the provider configuration to a JSON map conforming to schema.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'providerType': providerType,
      'displayName': displayName,
      'modelName': modelName,
      'customEndpointUrl': customEndpointUrl,
      'temperature': temperature,
      'maxOutputTokens': maxOutputTokens,
      'isActive': isActive,
      'customHeaders': customHeaders,
      'extraConfig': extraConfig,
    };
  }

  /// Deserializes a provider configuration from a JSON map.
  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      id: json['id'] as String,
      providerType: json['providerType'] as String,
      displayName: json['displayName'] as String,
      modelName: json['modelName'] as String,
      customEndpointUrl: json['customEndpointUrl'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxOutputTokens: json['maxOutputTokens'] as int? ?? 4096,
      isActive: json['isActive'] as bool? ?? false,
      customHeaders: json['customHeaders'] != null
          ? Map<String, String>.from(json['customHeaders'] as Map)
          : const {},
      extraConfig: json['extraConfig'] != null
          ? Map<String, dynamic>.from(json['extraConfig'] as Map)
          : const {},
    );
  }

  /// Creates a copy of this configuration with the specified fields replaced.
  ProviderConfig copyWith({
    String? id,
    String? providerType,
    String? displayName,
    String? modelName,
    String? customEndpointUrl,
    double? temperature,
    int? maxOutputTokens,
    bool? isActive,
    Map<String, String>? customHeaders,
    Map<String, dynamic>? extraConfig,
  }) {
    return ProviderConfig(
      id: id ?? this.id,
      providerType: providerType ?? this.providerType,
      displayName: displayName ?? this.displayName,
      modelName: modelName ?? this.modelName,
      customEndpointUrl: customEndpointUrl ?? this.customEndpointUrl,
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      isActive: isActive ?? this.isActive,
      customHeaders: customHeaders ?? this.customHeaders,
      extraConfig: extraConfig ?? this.extraConfig,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          providerType == other.providerType &&
          modelName == other.modelName &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^
      providerType.hashCode ^
      modelName.hashCode ^
      isActive.hashCode;
}
