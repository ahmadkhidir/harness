import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import 'model_http_retry.dart';
import 'model_provider.dart';

/// Adapter for Anthropic Claude models via the Messages API.
class ClaudeModelProvider extends ModelProvider {
  @override
  final ProviderConfig config;
  final http.Client? client;

  ClaudeModelProvider({required this.config, this.client});

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
        provider: 'claude',
        message: 'Anthropic Claude API key is missing. Please set your API key in Settings.',
      );
    }

    final c = client ?? http.Client();
    final url = Uri.parse('https://api.anthropic.com/v1/messages');

    final anthropicMessages = messages
        .where((m) => m.role != 'system')
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final payload = {
      'model': config.modelName,
      'max_tokens': config.maxOutputTokens,
      'temperature': config.temperature,
      'system': ?systemInstruction,
      'messages': anthropicMessages,
    };

    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
    };

    final response = await ModelHttpRetry.post(
      client: c,
      url: url,
      headers: headers,
      body: json.encode(payload),
      provider: 'claude',
      onRetry: emitRetry,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthenticationException(
        provider: 'claude',
        statusCode: response.statusCode,
        message: 'Invalid or expired Anthropic Claude API key: ${response.body}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final content = data['content'] as List?;
      if (content != null) {
        final buffer = StringBuffer();
        for (final block in content) {
          // Extended-thinking models return separate `thinking` blocks; skip
          // anything that is not an explicit text block.
          if (block is! Map || block['type'] != 'text') continue;
          final text = block['text'] as String?;
          if (text != null) buffer.write(text);
        }
        return stripInlineReasoning(buffer.toString());
      }
      return '';
    } else {
      throw ModelProviderException(
        provider: 'claude',
        statusCode: response.statusCode,
        message: 'Claude API error: ${response.body}',
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
