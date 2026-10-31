import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import 'model_provider.dart';

/// Generic adapter for OpenAI-compatible inference servers (Ollama, vLLM, DeepSeek, LocalAI).
class OpenAICompatibleProvider extends ModelProvider {
  @override
  final ProviderConfig config;
  final http.Client? client;

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
      if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      ...config.customHeaders,
    };

    final response = await c.post(
      url,
      headers: headers,
      body: json.encode(payload),
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
        return choices[0]['message']['content'] as String? ?? '';
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
