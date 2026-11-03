import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import 'model_provider.dart';

/// Adapter for Google Gemini models via the Gemini REST API.
class GeminiModelProvider extends ModelProvider {
  @override
  final ProviderConfig config;
  final http.Client? client;

  GeminiModelProvider({required this.config, this.client});

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
        provider: 'gemini',
        message: 'Google Gemini API key is missing. Please set your API key in Settings.',
      );
    }

    final c = client ?? http.Client();
    final model = config.modelName;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
    );

    final contents = messages.map((m) {
      return {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m.content}
        ],
      };
    }).toList();

    final payload = {
      'contents': contents,
      if (systemInstruction != null)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction}
          ],
        },
      'generationConfig': {
        'temperature': config.temperature,
        'maxOutputTokens': config.maxOutputTokens,
      },
    };

    final response = await c.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(payload),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthenticationException(
        provider: 'gemini',
        statusCode: response.statusCode,
        message: 'Invalid or expired Google Gemini API key: ${response.body}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates[0]['content']['parts'] as List?;
        if (parts != null) {
          final buffer = StringBuffer();
          for (final part in parts) {
            if (part is! Map) continue;
            // Thinking models flag chain-of-thought parts; never parse or show them.
            if (part['thought'] == true) continue;
            final text = part['text'] as String?;
            if (text != null) buffer.write(text);
          }
          return stripInlineReasoning(buffer.toString());
        }
      }
      return '';
    } else {
      throw ModelProviderException(
        provider: 'gemini',
        statusCode: response.statusCode,
        message: 'Gemini API error: ${response.body}',
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
    // Yield generated text in chunks without stutter
    final chunkSize = 20;
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      yield text.substring(i, end);
    }
  }
}
