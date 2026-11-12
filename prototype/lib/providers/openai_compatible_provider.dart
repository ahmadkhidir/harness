import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import 'model_http_retry.dart';
import 'model_provider.dart';

/// Generic adapter for OpenAI-compatible inference servers (OpenCode, Ollama,
/// vLLM, DeepSeek, LocalAI).
class OpenAICompatibleProvider extends ModelProvider {
  @override
  final ProviderConfig config;
  final http.Client? client;

  /// Stable fallback used when no conversation id has been supplied (for
  /// example when the adapter is driven directly from a test).
  final String _fallbackSessionId = const Uuid().v4();

  OpenAICompatibleProvider({required this.config, this.client});

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    final c = client ?? http.Client();
    final baseUrl = config.customEndpointUrl ?? 'http://localhost:11434/v1';
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$normalized/chat/completions');

    final chatMessages = <Map<String, String>>[];
    if (systemInstruction != null) {
      chatMessages.add({'role': 'system', 'content': systemInstruction});
    }
    for (final m in messages) {
      chatMessages.add({'role': m.role, 'content': m.content});
    }

    final payload = {
      'model': config.modelName,
      'messages': chatMessages,
      'temperature': config.temperature,
      'max_tokens': config.maxOutputTokens,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      // OpenCode Go rejects requests without a stable session id. The engine
      // supplies the active conversation id; fall back to a provider-scoped id
      // when the adapter is used outside the engine. Other OpenAI-compatible
      // servers ignore unknown headers, so this is safe for every endpoint.
      'x-opencode-session': sessionId ?? _fallbackSessionId,
      // OpenCode asks clients to identify themselves instead of relying on the
      // generic default HTTP-library user agent.
      'User-Agent': 'harness/1.0',
      if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      ...config.customHeaders,
    };

    final response = await ModelHttpRetry.post(
      client: c,
      url: url,
      headers: headers,
      body: json.encode(payload),
      provider: 'openai_compatible',
      onRetry: emitRetry,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthenticationException(
        provider: 'openai_compatible',
        statusCode: response.statusCode,
        message: 'Authorization failed for OpenAI-compatible endpoint ($baseUrl): ${response.body}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']['content'] as String? ?? '';
        return stripInlineReasoning(content);
      }
      return '';
    } else {
      throw ModelProviderException(
        provider: 'openai_compatible',
        statusCode: response.statusCode,
        message: 'Endpoint error from $baseUrl: ${response.body}',
      );
    }
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    final text = await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
    final chunkSize = 20;
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      yield text.substring(i, end);
    }
  }
}
