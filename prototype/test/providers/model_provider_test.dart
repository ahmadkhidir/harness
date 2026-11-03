import 'dart:convert';
import 'dart:io';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:harness/core/models/provider_config.dart';
import 'package:harness/providers/claude_model_provider.dart';
import 'package:harness/providers/gemini_model_provider.dart';
import 'package:harness/providers/local_device_model_provider.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:harness/providers/model_provider_factory.dart';
import 'package:harness/providers/openai_compatible_provider.dart';
import 'package:harness/providers/openai_model_provider.dart';
import '../mocks/mock_on_device_engine.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class MockOnDeviceEngine implements OnDeviceInferenceEngine {
  final Future<String> Function(String prompt)? onGenerate;
  final Stream<String> Function(String prompt)? onStreamGenerate;
  int memoryUsageMb;
  bool isUnloaded = false;

  MockOnDeviceEngine({
    this.onGenerate,
    this.onStreamGenerate,
    this.memoryUsageMb = 256,
  });

  @override
  Future<String> generate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async {
    if (onGenerate != null) return onGenerate!(prompt);
    return 'On-device response: <system_call>{"command": "send_message", "parameters": {"text": "Done"}}</system_call>';
  }

  @override
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async* {
    if (onStreamGenerate != null) {
      yield* onStreamGenerate!(prompt);
      return;
    }
    yield 'On-device ';
    yield 'streamed ';
    yield 'tokens.';
  }

  @override
  Future<int> getMemoryUsageMb() async => memoryUsageMb;

  @override
  Future<void> unload() async {
    isUnloaded = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelProvider Adapters & Factory Tests', () {
    test('GeminiModelProvider throws AuthenticationException when API key is missing', () async {
      final config = ProviderConfig(
        id: 'gemini',
        providerType: 'gemini',
        displayName: 'Gemini',
        modelName: 'gemini-2.0-flash',
      );
      final provider = GeminiModelProvider(config: config);

      expect(
        () => provider.generate(messages: [
          const ModelMessage(role: 'user', content: 'Hello'),
        ]),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('GeminiModelProvider generates text and parses system calls successfully', () async {
      final config = ProviderConfig(
        id: 'gemini',
        providerType: 'gemini',
        displayName: 'Gemini',
        modelName: 'gemini-2.0-flash',
      );

      final client = MockHttpClient((request) async {
        expect(request.url.toString(), contains('generativelanguage.googleapis.com'));
        expect(request.url.queryParameters['key'], equals('test_gemini_key'));

        final responsePayload = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        'Let me check the battery: <system_call>{"command": "get_battery", "parameters": {}}</system_call>',
                  }
                ],
              },
            }
          ],
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = GeminiModelProvider(config: config, client: client);
      final response = await provider.generateResponse(
        messages: [const ModelMessage(role: 'user', content: 'What is battery level?')],
        apiKey: 'test_gemini_key',
      );

      expect(response.text, contains('<system_call>'));
      expect(response.systemCalls.length, equals(1));
      expect(response.systemCalls.first.command, equals('get_battery'));
    });

    test('GeminiModelProvider skips thought parts and concatenates text parts', () async {
      final config = ProviderConfig(
        id: 'gemini',
        providerType: 'gemini',
        displayName: 'Gemini',
        modelName: 'gemini-2.5-flash',
      );

      final client = MockHttpClient((request) async {
        final responsePayload = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'internal reasoning', 'thought': true},
                  {'text': 'Hello! '},
                  {'text': 'How can I help?'},
                ],
              },
            }
          ],
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = GeminiModelProvider(config: config, client: client);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hello')],
        apiKey: 'test_gemini_key',
      );

      expect(text, equals('Hello! How can I help?'));
    });

    test('OpenAICompatibleProvider strips inline reasoning tags', () async {
      final config = ProviderConfig(
        id: 'ollama_reasoner',
        providerType: 'openai_compatible',
        displayName: 'Local Reasoner',
        modelName: 'deepseek-r1:7b',
        customEndpointUrl: 'http://localhost:11434/v1',
      );

      final client = MockHttpClient((request) async {
        final responsePayload = {
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '<think>pondering the request</think>Final answer',
              },
            }
          ]
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = OpenAICompatibleProvider(config: config, client: client);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hi')],
      );

      expect(text, equals('Final answer'));
    });

    test('LocalDeviceModelProvider strips inline reasoning from on-device output', () async {
      final engine = MockOnDeviceEngine(
        onGenerate: (prompt) async => '<think>internal reasoning</think>Hi from the device',
      );
      final config = ProviderConfig(
        id: 'local_slm',
        providerType: 'local_device',
        displayName: 'Local SLM',
        modelName: 'local-slm-1b',
      );

      final provider = LocalDeviceModelProvider(config: config, engine: engine);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hi')],
      );

      expect(text, equals('Hi from the device'));
    });

    test('GeminiModelProvider throws AuthenticationException on 401/403', () async {
      final config = ProviderConfig(
        id: 'gemini',
        providerType: 'gemini',
        displayName: 'Gemini',
        modelName: 'gemini-2.0-flash',
      );

      final client = MockHttpClient((request) async {
        return http.Response('{"error": {"message": "API key not valid"}}', 401);
      });

      final provider = GeminiModelProvider(config: config, client: client);
      expect(
        () => provider.generate(
          messages: [const ModelMessage(role: 'user', content: 'Hi')],
          apiKey: 'bad_key',
        ),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('ClaudeModelProvider generates response with correct Anthropic headers', () async {
      final config = ProviderConfig(
        id: 'claude',
        providerType: 'claude',
        displayName: 'Claude',
        modelName: 'claude-3-7-sonnet-20250219',
      );

      final client = MockHttpClient((request) async {
        expect(request.headers['x-api-key'], equals('test_claude_key'));
        expect(request.headers['anthropic-version'], equals('2023-06-01'));

        final responsePayload = {
          'content': [
            {'type': 'text', 'text': 'Hello from Claude'}
          ]
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = ClaudeModelProvider(config: config, client: client);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hello')],
        apiKey: 'test_claude_key',
      );

      expect(text, equals('Hello from Claude'));
    });

    test('OpenAIModelProvider generates response with Bearer authorization', () async {
      final config = ProviderConfig(
        id: 'openai',
        providerType: 'openai',
        displayName: 'OpenAI',
        modelName: 'gpt-4o',
      );

      final client = MockHttpClient((request) async {
        expect(request.headers['authorization'], equals('Bearer test_openai_key'));

        final responsePayload = {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Hello from GPT-4o'},
            }
          ]
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = OpenAIModelProvider(config: config, client: client);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hello')],
        apiKey: 'test_openai_key',
      );

      expect(text, equals('Hello from GPT-4o'));
    });

    test('OpenAICompatibleProvider routes to custom base URL and attaches custom headers',
        () async {
      final config = ProviderConfig(
        id: 'ollama',
        providerType: 'openai_compatible',
        displayName: 'Local Ollama',
        modelName: 'llama3:8b',
        customEndpointUrl: 'http://192.168.1.100:11434/v1',
        customHeaders: {'X-Custom-Client': 'HarnessMobile'},
      );

      final client = MockHttpClient((request) async {
        expect(
          request.url.toString(),
          equals('http://192.168.1.100:11434/v1/chat/completions'),
        );
        expect(request.headers['x-custom-client'], equals('HarnessMobile'));

        final responsePayload = {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Response from local Llama 3'},
            }
          ]
        };
        return http.Response(json.encode(responsePayload), 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = OpenAICompatibleProvider(config: config, client: client);
      final text = await provider.generate(
        messages: [const ModelMessage(role: 'user', content: 'Hello local model')],
      );

      expect(text, equals('Response from local Llama 3'));
    });

    test('LocalDeviceModelProvider formats prompt and generates response via engine', () async {
      String receivedPrompt = '';
      final engine = MockOnDeviceEngine(
        onGenerate: (prompt) async {
          receivedPrompt = prompt;
          return 'Local inference output: <system_call>{"command": "read_file", "parameters": {"path": "notes.txt"}}</system_call>';
        },
      );

      final config = ProviderConfig(
        id: 'local_slm',
        providerType: 'local_device',
        displayName: 'Local SLM',
        modelName: 'local-slm-1b',
      );

      final provider = LocalDeviceModelProvider(config: config, engine: engine);
      final response = await provider.generateResponse(
        systemInstruction: 'You are an offline assistant.',
        messages: [const ModelMessage(role: 'user', content: 'What is local?')],
      );

      expect(receivedPrompt, contains('<|im_start|>system'));
      expect(receivedPrompt, contains('You are an offline assistant.'));
      expect(receivedPrompt, contains('<|im_start|>user'));
      expect(receivedPrompt, contains('What is local?'));
      expect(response.systemCalls.length, equals(1));
      expect(response.systemCalls.first.command, equals('read_file'));
    });

    test('LocalDeviceModelProvider halts when memory threshold is exceeded', () async {
      final config = ProviderConfig(
        id: 'local_slm',
        providerType: 'local_device',
        displayName: 'Local SLM',
        modelName: 'local-slm-1b',
        extraConfig: {'simulatedAllocatedMb': 3000}, // Exceeds 2048 MB default
      );

      final provider = LocalDeviceModelProvider(config: config, maxMemoryBudgetMb: 2048);

      expect(
        () => provider.generate(messages: [const ModelMessage(role: 'user', content: 'Run SLM')]),
        throwsA(isA<ModelMemoryExceededException>()),
      );
    });

    test('PlatformChannelInferenceEngine throws ModelProviderException when native channel is unregistered', () async {
      const engine = PlatformChannelInferenceEngine();
      expect(
        () => engine.generate('Test prompt'),
        throwsA(isA<ModelProviderException>()),
      );
    });

    test('FlutterEdgeAiInferenceEngine throws ModelProviderException when model is not downloaded', () async {
      final engine = FlutterEdgeAiInferenceEngine();
      expect(
        () => engine.generate('Test prompt', modelPath: 'missing_model.litertlm'),
        throwsA(isA<ModelProviderException>()),
      );
    });

    test('FlutterEdgeAiInferenceEngine rejects model files smaller than 1MB', () async {
      final tempDir = await Directory.systemTemp.createTemp('litert_size_test_');
      try {
        final smallFile = File('${tempDir.path}/small_model.litertlm');
        await smallFile.writeAsString('short stub content');

        final engine = FlutterEdgeAiInferenceEngine();
        await expectLater(
          () => engine.generate('Test prompt', modelPath: smallFile.path),
          throwsA(isA<ModelProviderException>().having(
            (e) => e.message,
            'message',
            contains('incomplete or empty'),
          )),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('FlutterEdgeAiInferenceEngine normalizes and sanitizes spaced model paths', () async {
      final engine = FlutterEdgeAiInferenceEngine();
      // Even with quotes and whitespace around slashes, it should extract the clean filename
      await expectLater(
        () => engine.generate(
          'Test prompt',
          modelPath: '"/ storage/emulated/0/Harness/data/models/ Qwen3-0.6B.litertlm"',
        ),
        throwsA(isA<ModelProviderException>().having(
          (e) => e.message,
          'message',
          contains('Qwen3-0.6B.litertlm'),
        )),
      );
    });
    test('FlutterEdgeAiInferenceEngine.inferFileType identifies .litertlm, .task, .bin formats', () {
      expect(
        FlutterEdgeAiInferenceEngine.inferFileType('model.litertlm'),
        equals(ModelFileType.litertlm),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferFileType('model.task'),
        equals(ModelFileType.task),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferFileType('model.bin'),
        equals(ModelFileType.binary),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferFileType('model.tflite'),
        equals(ModelFileType.binary),
      );
    });

    test('FlutterEdgeAiInferenceEngine.inferModelType maps family names', () {
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('gemma-4-E2B-it.litertlm'),
        equals(ModelType.gemma4),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('gemma-2-2b-it.litertlm'),
        equals(ModelType.gemmaIt),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('qwen2.5-1.5b.litertlm'),
        equals(ModelType.qwen),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('DeepSeek-R1.task'),
        equals(ModelType.deepSeek),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('Llama-3.2.bin'),
        equals(ModelType.llama),
      );
      expect(
        FlutterEdgeAiInferenceEngine.inferModelType('custom_model.litertlm'),
        equals(ModelType.general),
      );
    });

    test('FlutterEdgeAiInferenceEngine throws ModelProviderException when model is not downloaded', () async {
      final engine = FlutterEdgeAiInferenceEngine();
      await expectLater(
        () => engine.generate('Test prompt', modelPath: 'missing_model.litertlm'),
        throwsA(isA<ModelProviderException>().having(
          (e) => e.message,
          'message',
          contains('missing_model.litertlm'),
        )),
      );
    });

    test('LocalDeviceModelProvider routes to FlutterEdgeAiInferenceEngine for on-device inference', () {
      final litertConfig = ProviderConfig(
        id: 'litert_model',
        providerType: 'local_device',
        displayName: 'LiteRT Model',
        modelName: 'gemma-4-E2B-it.litertlm',
      );
      final litertProvider = LocalDeviceModelProvider(config: litertConfig);
      expect(litertProvider.engine, isA<FlutterEdgeAiInferenceEngine>());

      final qwenConfig = ProviderConfig(
        id: 'qwen_model',
        providerType: 'local_device',
        displayName: 'Qwen Model',
        modelName: 'Qwen3-0.6B.litertlm',
      );
      final qwenProvider = LocalDeviceModelProvider(config: qwenConfig);
      expect(qwenProvider.engine, isA<FlutterEdgeAiInferenceEngine>());
    });
    test('LocalDeviceModelProvider with test StubOnDeviceInferenceEngine produces structured output', () async {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'Qwen 2.5 (1.5B)',
        extraConfig: {'modelPath': 'Qwen3-0.6B.litertlm'},
      );

      final provider = LocalDeviceModelProvider(
        config: config,
        engine: const StubOnDeviceInferenceEngine(),
      );
      final response = await provider.generateResponse(
        messages: [const ModelMessage(role: 'user', content: 'List files in workspace')],
      );

      expect(response.text, contains('<system_call>'));
      expect(response.systemCalls.isNotEmpty, isTrue);
      expect(response.systemCalls.first.command, equals('list_directory'));
    });

    test('StubOnDeviceInferenceEngine alerts user when no model has been downloaded yet', () async {
      final config = ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'None (Download required)',
        extraConfig: {'modelPath': ''},
      );

      final provider = LocalDeviceModelProvider(
        config: config,
        engine: const StubOnDeviceInferenceEngine(),
      );
      final response = await provider.generateResponse(
        messages: [const ModelMessage(role: 'user', content: 'Test prompt')],
      );

      expect(response.text, contains('No On-Device Model Downloaded'));
    });

    test('ModelProviderFactory creates matching adapter instances', () {
      final gemini = ModelProviderFactory.create(
        config: ProviderConfig(
            id: '1', providerType: 'gemini', displayName: 'G', modelName: 'gemini-2.0-flash'),
      );
      expect(gemini, isA<GeminiModelProvider>());

      final claude = ModelProviderFactory.create(
        config: ProviderConfig(
            id: '2', providerType: 'claude', displayName: 'C', modelName: 'claude-3-7-sonnet-20250219'),
      );
      expect(claude, isA<ClaudeModelProvider>());

      final openai = ModelProviderFactory.create(
        config: ProviderConfig(
            id: '3', providerType: 'openai', displayName: 'O', modelName: 'gpt-4o'),
      );
      expect(openai, isA<OpenAIModelProvider>());

      final compat = ModelProviderFactory.create(
        config: ProviderConfig(
            id: '4', providerType: 'openai_compatible', displayName: 'L', modelName: 'llama3'),
      );
      expect(compat, isA<OpenAICompatibleProvider>());

      final local = ModelProviderFactory.create(
        config: ProviderConfig(
            id: '5', providerType: 'local_device', displayName: 'S', modelName: 'slm-1b'),
      );
      expect(local, isA<LocalDeviceModelProvider>());
    });
  });
}
