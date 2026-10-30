import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';

/// A standardized message exchanged with an LLM inference provider.
class ModelMessage {
  /// The message originator role: `'system'`, `'user'`, or `'assistant'`.
  final String role;

  /// The plaintext or XML content of the message.
  final String content;

  const ModelMessage({
    required this.role,
    required this.content,
  });

  /// Serializes the model message to a JSON map.
  Map<String, String> toJson() => {'role': role, 'content': content};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelMessage &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          content == other.content;

  @override
  int get hashCode => role.hashCode ^ content.hashCode;
}

/// Abstract contract for LLM inference providers in Harness.
///
/// Implements the pluggable provider layer specified in `docs/Harness/architecture.md`.
/// Concrete implementations exist for Google Gemini, Anthropic Claude, OpenAI,
/// OpenAI-compatible local endpoints (Ollama/vLLM), and on-device SLM stubs.
abstract class ModelProvider {
  /// The configuration metadata describing this provider.
  ProviderConfig get config;

  /// Generates a complete text response from the model for the given conversation history.
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  });

  /// Streams generated tokens incrementally as they arrive from the inference stream.
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  });
}
