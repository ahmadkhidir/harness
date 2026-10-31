import '../core/engine/system_call_parser.dart';
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import '../core/models/system_call.dart';

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

/// Standardized response container returned by model providers.
class ModelResponse {
  /// Raw or formatted generated text.
  final String text;

  /// Parsed system calls extracted from the output.
  final List<SystemCall> systemCalls;

  /// Optional generation completion reason (e.g. `'stop'`, `'length'`).
  final String? finishReason;

  /// Count of prompt tokens consumed.
  final int? promptTokens;

  /// Count of completion tokens generated.
  final int? completionTokens;

  const ModelResponse({
    required this.text,
    this.systemCalls = const [],
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });
}

/// Base exception thrown by model provider adapters during inference or transport failures.
class ModelProviderException implements Exception {
  final String provider;
  final String message;
  final int? statusCode;

  const ModelProviderException({
    required this.provider,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() =>
      'ModelProviderException ($provider${statusCode != null ? ', status $statusCode' : ''}): $message';
}

/// Thrown when an API key is missing, invalid, or expired (HTTP 401/403).
class AuthenticationException extends ModelProviderException {
  const AuthenticationException({
    required super.provider,
    required super.message,
    super.statusCode = 401,
  });
}

/// Thrown when an on-device local SLM exceeds memory or device limits.
class ModelMemoryExceededException extends ModelProviderException {
  const ModelMemoryExceededException({
    required super.provider,
    required super.message,
  });
}

/// Abstract contract for LLM inference providers in Harness.
///
/// Implements the pluggable provider layer specified in `docs/Harness/architecture.md`
/// and `docs/Harness/features/FEAT-002.md`.
/// Concrete implementations exist for Google Gemini, Anthropic Claude, OpenAI,
/// OpenAI-compatible local endpoints (Ollama/vLLM), and on-device SLMs (Google LiteRT-LM / flutter_edge_ai).
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

  /// Generates a standardized [ModelResponse] with parsed tool calls.
  Future<ModelResponse> generateResponse({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    final rawText = await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
    final parsed = SystemCallParser.parse(rawText);
    return ModelResponse(
      text: rawText,
      systemCalls: parsed.systemCalls,
    );
  }
}
