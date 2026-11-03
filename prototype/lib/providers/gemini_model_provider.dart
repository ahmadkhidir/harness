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

    final supportsThinking = _supportsThinking(config.modelName);
    final configuredBudget = config.extraConfig['thinkingBudget'];
    final thinkingBudget = configuredBudget is int ? configuredBudget : null;

    var result = await _request(
      key: key,
      messages: messages,
      systemInstruction: systemInstruction,
      thinkingBudget: supportsThinking ? thinkingBudget : null,
    );

    // Gemini occasionally attempts native function calling even though Harness
    // uses a text protocol, ending with MALFORMED_FUNCTION_CALL and no answer.
    // Retry once with an explicit correction.
    if (result.text.trim().isEmpty &&
        result.finishReason == 'MALFORMED_FUNCTION_CALL') {
      result = await _request(
        key: key,
        messages: [
          ...messages,
          const ModelMessage(
            role: 'user',
            content:
                'Your previous response was rejected as a malformed function call. '
                'Do not use native function calling. Reply with plain text or a single '
                '<system_call> JSON block.',
          ),
        ],
        systemInstruction: systemInstruction,
        thinkingBudget: supportsThinking ? 0 : null,
      );
    }

    // Thinking models can spend the whole output budget on reasoning and return
    // no answer. Retry once with reasoning disabled so simple prompts still
    // complete instead of surfacing an empty reply.
    if (result.text.trim().isEmpty &&
        supportsThinking &&
        result.finishReason == 'MAX_TOKENS' &&
        thinkingBudget != 0) {
      result = await _request(
        key: key,
        messages: messages,
        systemInstruction: systemInstruction,
        thinkingBudget: 0,
      );
    }

    if (result.text.trim().isEmpty) {
      throw _emptyResponseException(result);
    }

    return stripInlineReasoning(result.text);
  }

  /// Performs a single generateContent request and normalizes the response.
  Future<_GeminiResponse> _request({
    required String key,
    required List<ModelMessage> messages,
    required String? systemInstruction,
    required int? thinkingBudget,
  }) async {
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
        'responseMimeType': 'text/plain',
        if (thinkingBudget != null)
          'thinkingConfig': {'thinkingBudget': thinkingBudget},
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelProviderException(
        provider: 'gemini',
        statusCode: response.statusCode,
        message: 'Gemini API error: ${response.body}',
      );
    }

    final decoded = json.decode(response.body);
    final data = decoded is Map ? decoded : const {};

    final blockReason = data['promptFeedback'] is Map
        ? (data['promptFeedback'] as Map)['blockReason']?.toString()
        : null;

    var text = '';
    String? finishReason;
    final partTypes = <String>[];

    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final candidate = candidates.first;
      if (candidate is Map) {
        finishReason = candidate['finishReason']?.toString();
        final content = candidate['content'];
        final parts = content is Map ? content['parts'] : null;
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map) continue;
            // Thinking models flag chain-of-thought parts; never parse or show them.
            if (part['thought'] == true) {
              partTypes.add('thought');
              continue;
            }
            final partText = part['text'];
            if (partText is String) {
              text += partText;
              partTypes.add('text');
            } else if (part.isNotEmpty) {
              partTypes.add(part.keys.first.toString());
            }
          }
        }
      }
    }

    return _GeminiResponse(
      text: text,
      finishReason: finishReason,
      blockReason: blockReason,
      partTypes: partTypes,
    );
  }

  /// Builds an actionable error for an empty Gemini response.
  ModelProviderException _emptyResponseException(_GeminiResponse result) {
    if (result.blockReason != null && result.blockReason!.isNotEmpty) {
      return ModelProviderException(
        provider: 'gemini',
        message:
            'Gemini blocked the request (reason: ${result.blockReason}). Try rewording or switching providers.',
      );
    }

    if (result.finishReason == 'MALFORMED_FUNCTION_CALL') {
      return ModelProviderException(
        provider: 'gemini',
        message:
            'Gemini produced a malformed function call instead of a reply. '
            'Retry the action, rephrase the request, or switch providers.',
      );
    }

    if (result.finishReason == 'MAX_TOKENS') {
      return ModelProviderException(
        provider: 'gemini',
        message:
            'Gemini reached its output limit before answering '
            '(maxOutputTokens: ${config.maxOutputTokens}). Increase Max Output Tokens in Settings, then retry.',
      );
    }

    if (result.finishReason == 'SAFETY' ||
        result.finishReason == 'RECITATION' ||
        result.finishReason == 'PROHIBITED_CONTENT') {
      return ModelProviderException(
        provider: 'gemini',
        message:
            'Gemini stopped the response (finish reason: ${result.finishReason}). Try rewording the request.',
      );
    }

    final reason =
        result.finishReason == null ? '' : ' (finish reason: ${result.finishReason})';
    final parts =
        result.partTypes.isEmpty ? '' : ' Parts: ${result.partTypes.join(', ')}.';
    return ModelProviderException(
      provider: 'gemini',
      message: 'Gemini returned no text$reason.$parts',
    );
  }

  bool _supportsThinking(String modelName) {
    final name = modelName.toLowerCase();
    return name.contains('2.5') || name.contains('thinking');
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

class _GeminiResponse {
  final String text;
  final String? finishReason;
  final String? blockReason;
  final List<String> partTypes;

  const _GeminiResponse({
    required this.text,
    required this.finishReason,
    required this.blockReason,
    required this.partTypes,
  });
}
