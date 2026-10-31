import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import 'model_provider.dart';

/// Adapter for OpenAI models via the Chat Completions API.
class OpenAIModelProvider extends ModelProvider {
  @override
  final ProviderConfig config;
  final http.Client? client;

  OpenAIModelProvider({required this.config, this.client});

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    final key = apiKey ?? '';
    if (key.trim().isEmpty) {
      throw const AuthenticationException(
        provider: 'openai',
        message: 'OpenAI API key is missing. Please set your API key in Settings.',
      );
    }

    final c = client ?? http.Client();
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');

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

    final response = await c.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: json.encode(payload),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthenticationException(
        provider: 'openai',
        statusCode: response.statusCode,
        message: 'Invalid or expired OpenAI API key: ${response.body}',
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
        provider: 'openai',
        statusCode: response.statusCode,
        message: 'OpenAI API error: ${response.body}',
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
