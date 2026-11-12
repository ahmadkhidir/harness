import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/command_definition.dart';
import 'package:harness/core/models/provider_config.dart';
import 'package:harness/core/models/system_response.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/secure_storage/key_storage_service.dart';
import 'package:harness/modules/base/harness_module.dart';
import 'package:harness/presentation/bloc/harness_session_bloc.dart';
import 'package:harness/presentation/bloc/harness_session_event.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/presentation/bloc/model_switcher_bloc.dart';
import 'package:harness/presentation/bloc/model_switcher_event.dart';
import 'package:harness/presentation/bloc/model_switcher_state.dart';
import 'package:harness/providers/gemini_model_provider.dart';
import 'package:harness/providers/local_device_model_provider.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:harness/providers/openai_compatible_provider.dart';
import 'package:http/http.dart' as http;

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

class MockCommandModule extends HarnessModule {
  @override
  String get moduleName => 'device';

  @override
  List<CommandDefinition> get commands => [
    CommandDefinition(
      command: 'get_device_status',
      description: 'Gets current battery and network status',
      parametersSchema: const {'type': 'object'},
    ),
  ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    return SystemResponse.success(
      command: command,
      data: {'battery': 98, 'network': 'wifi'},
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
    int contextWindowTokens = 4096,
    String? modelPath,
  }) async {
    if (onGenerate != null) return onGenerate!(prompt);
    return 'On-device response: <system_call>{"command": "send_ui_message", "parameters": {"message": "Device response"}}</system_call>';
  }

  @override
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    int contextWindowTokens = 4096,
    String? modelPath,
  }) async* {
    if (onStreamGenerate != null) {
      yield* onStreamGenerate!(prompt);
      return;
    }
    yield '<system_call>';
    yield '{"command": "send_ui_message", "parameters": {"message": "Streamed on-device token chunks"}}';
    yield '</system_call>';
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

  late Directory tempDir;
  late AppDatabase db;
  late KeyStorageService keyStorage;
  late CommandRouter commandRouter;
  late ContextBuilder contextBuilder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('feat_002_acceptance_');
    db = AppDatabase.inMemory();
    await HarnessFileSystem.init(tempDir, db);
    keyStorage = KeyStorageService(useInMemoryFallback: true);

    commandRouter = CommandRouter();
    commandRouter.registerModule(MockCommandModule());
    contextBuilder = ContextBuilder();
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group(
    'FEAT-002 Acceptance Tests - Pluggable ModelProvider & Runtime Model Switcher',
    () {
      test(
        'Criterion 1: User inputs API key for Gemini and selects gemini-2.0-flash -> key encrypted in keystore and subsequent turns use Gemini adapter',
        () async {
          // 1. Initial engine configured with a baseline provider
          final initialConfig = ProviderConfig(
            id: 'initial',
            providerType: 'local_device',
            displayName: 'Initial Stub',
            modelName: 'initial-stub',
          );
          final engine = HarnessEngine(
            router: commandRouter,
            contextBuilder: contextBuilder,
            modelProvider: LocalDeviceModelProvider(config: initialConfig),
          );

          final switcherBloc = ModelSwitcherBloc(
            database: db,
            keyStorage: keyStorage,
            engine: engine,
          );

          // Load configs from database
          switcherBloc.add(const LoadProviderConfigsEvent());
          await expectLater(
            switcherBloc.stream,
            emitsInOrder([
              isA<ModelSwitcherLoading>(),
              isA<ModelSwitcherLoaded>().having(
                (s) => s.configs.length,
                'configs count',
                5,
              ),
            ]),
          );

          // 2. User inputs API key for Google Gemini
          switcherBloc.add(
            const SaveApiKeyForProviderEvent(
              providerId: 'gemini',
              apiKey: 'sk-gemini-test-secret-key-12345',
            ),
          );

          await expectLater(
            switcherBloc.stream,
            emits(
              isA<ModelSwitcherLoaded>().having(
                (s) => s.hasKeyMap['gemini'],
                'gemini has key',
                isTrue,
              ),
            ),
          );

          // Verify key is securely stored
          final storedKey = await keyStorage.getApiKey('gemini');
          expect(storedKey, equals('sk-gemini-test-secret-key-12345'));

          // 3. User selects gemini as the active provider
          switcherBloc.add(const SelectActiveProviderEvent('gemini'));

          await expectLater(
            switcherBloc.stream,
            emits(
              isA<ModelSwitcherLoaded>().having(
                (s) => s.activeConfig.id,
                'activeConfig id',
                equals('gemini'),
              ),
            ),
          );

          // Verify the engine's active model provider was swapped to GeminiModelProvider with gemini-2.0-flash
          expect(engine.modelProvider, isA<GeminiModelProvider>());
          expect(
            engine.modelProvider.config.modelName,
            equals('gemini-2.0-flash'),
          );

          // 4. Set up mock HTTP response for Gemini and verify subsequent turn execution uses the saved key
          var capturedApiKey = '';
          final mockGeminiClient = MockHttpClient((request) async {
            capturedApiKey = request.url.queryParameters['key'] ?? '';
            final responsePayload = {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            'Device status is healthy! <system_call>{"command": "send_ui_message", "parameters": {"message": "All good"}}</system_call>',
                      },
                    ],
                  },
                },
              ],
            };
            return http.Response(
              json.encode(responsePayload),
              200,
              headers: {'content-type': 'application/json'},
            );
          });

          // Update provider with mock client for test transport
          engine.updateModelProvider(
            GeminiModelProvider(
              config: engine.modelProvider.config,
              client: mockGeminiClient,
            ),
          );

          final sessionBloc = HarnessSessionBloc(
            engine: engine,
            keyStorage: keyStorage,
          );

          sessionBloc.add(
            const InitializeSessionEvent(sessionId: 'sess_gemini_test'),
          );
          await expectLater(
            sessionBloc.stream,
            emits(isA<HarnessSessionReady>()),
          );

          sessionBloc.add(const SubmitUserPromptEvent('Check system health'));

          await expectLater(
            sessionBloc.stream,
            emitsThrough(
              isA<HarnessSessionReady>().having(
                (s) => s.turns.last.text,
                'last turn text',
                equals('All good'),
              ),
            ),
          );

          // Verify Gemini API received the saved key from KeyStorageService
          expect(capturedApiKey, equals('sk-gemini-test-secret-key-12345'));

          await switcherBloc.close();
          await sessionBloc.close();
        },
      );

      test(
        'Criterion 2: OpenAI-compatible provider with custom base URL -> correctly routes calls with custom headers',
        () async {
          var requestedUrl = '';

          final client = MockHttpClient((request) async {
            requestedUrl = request.url.toString();
            expect(
              request.headers['x-local-network-token'],
              equals('lan-secret-xyz'),
            );
            expect(
              request.headers['x-client-agent'],
              equals('Harness-Mobile-002'),
            );

            final responsePayload = {
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'Response from custom Ollama server on LAN',
                  },
                },
              ],
            };
            return http.Response(
              json.encode(responsePayload),
              200,
              headers: {'content-type': 'application/json'},
            );
          });

          final config = ProviderConfig(
            id: 'ollama_lan',
            providerType: 'openai_compatible',
            displayName: 'Ollama LAN',
            modelName: 'llama3:8b',
            customEndpointUrl: 'http://192.168.1.100:11434/v1',
            customHeaders: {
              'X-Local-Network-Token': 'lan-secret-xyz',
              'X-Client-Agent': 'Harness-Mobile-002',
            },
          );

          final provider = OpenAICompatibleProvider(
            config: config,
            client: client,
          );

          final text = await provider.generate(
            messages: [
              const ModelMessage(role: 'user', content: 'Ping LAN model'),
            ],
          );

          expect(text, equals('Response from custom Ollama server on LAN'));
          expect(
            requestedUrl,
            equals('http://192.168.1.100:11434/v1/chat/completions'),
          );
        },
      );

      test(
        'Criterion 3: Active turn streaming tokens -> adapter yields tokens cleanly without stutter or memory leaks',
        () async {
          final config = ProviderConfig(
            id: 'local_slm_stream',
            providerType: 'local_device',
            displayName: 'Local SLM Stream',
            modelName: 'local-slm-1b',
          );

          final mockEngine = MockOnDeviceEngine(
            onStreamGenerate: (prompt) async* {
              yield '<system_call>';
              yield '{"command": "send_ui_message", "parameters": {"message": "Streamed on-device token chunks"}}';
              yield '</system_call>';
            },
          );
          final provider = LocalDeviceModelProvider(
            config: config,
            engine: mockEngine,
          );

          final streamedChunks = <String>[];
          await for (final chunk in provider.streamGenerate(
            messages: [
              const ModelMessage(role: 'user', content: 'Generate stream test'),
            ],
          )) {
            expect(chunk.isNotEmpty, isTrue);
            streamedChunks.add(chunk);
          }

          expect(streamedChunks.isNotEmpty, isTrue);
          final completeText = streamedChunks.join();
          expect(completeText, contains('send_ui_message'));
        },
      );

      test(
        'Edge Case 1: Provider API key is invalid or expired -> Immediate authentication error surfaced with isAuthError flag',
        () async {
          final config = ProviderConfig(
            id: 'gemini',
            providerType: 'gemini',
            displayName: 'Google Gemini Flash',
            modelName: 'gemini-2.0-flash',
          );

          // Return HTTP 401 Unauthorized for expired/invalid key
          final mockAuthFailureClient = MockHttpClient((request) async {
            return http.Response(
              json.encode({
                'error': {
                  'code': 401,
                  'message': 'API key expired or invalid.',
                  'status': 'UNAUTHENTICATED',
                },
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          });

          final provider = GeminiModelProvider(
            config: config,
            client: mockAuthFailureClient,
          );

          final engine = HarnessEngine(
            router: commandRouter,
            contextBuilder: contextBuilder,
            modelProvider: provider,
          );

          final sessionBloc = HarnessSessionBloc(
            engine: engine,
            keyStorage: keyStorage,
          );

          sessionBloc.add(
            const InitializeSessionEvent(sessionId: 'sess_auth_err'),
          );
          await expectLater(
            sessionBloc.stream,
            emits(isA<HarnessSessionReady>()),
          );

          // Submit prompt with invalid key
          sessionBloc.add(
            const SubmitUserPromptEvent(
              'Hello with expired key',
              apiKey: 'expired_invalid_key_999',
            ),
          );

          await expectLater(
            sessionBloc.stream,
            emitsThrough(
              isA<HarnessSessionError>()
                  .having((s) => s.isAuthError, 'isAuthError', isTrue)
                  .having(
                    (s) => s.errorMessage.toLowerCase(),
                    'errorMessage contains authentication/api key',
                    contains('api key'),
                  ),
            ),
          );

          await sessionBloc.close();
        },
      );

      test(
        'Edge Case 2: On-device local SLM exceeds mobile memory bounds -> cleanly halted and surfaced with isMemoryError flag',
        () async {
          final config = ProviderConfig(
            id: 'local_device',
            providerType: 'local_device',
            displayName: 'On-Device SLM (Stub)',
            modelName: 'local-slm-1b',
            extraConfig: {
              'simulatedAllocatedMb': 4096,
            }, // Exceeds default 2048 MB limit
          );

          final provider = LocalDeviceModelProvider(
            config: config,
            maxMemoryBudgetMb: 2048,
          );

          final engine = HarnessEngine(
            router: commandRouter,
            contextBuilder: contextBuilder,
            modelProvider: provider,
          );

          final sessionBloc = HarnessSessionBloc(
            engine: engine,
            keyStorage: keyStorage,
          );

          sessionBloc.add(
            const InitializeSessionEvent(sessionId: 'sess_mem_err'),
          );
          await expectLater(
            sessionBloc.stream,
            emits(isA<HarnessSessionReady>()),
          );

          sessionBloc.add(
            const SubmitUserPromptEvent('Run heavy on-device model'),
          );

          await expectLater(
            sessionBloc.stream,
            emitsThrough(
              isA<HarnessSessionError>()
                  .having((s) => s.isMemoryError, 'isMemoryError', isTrue)
                  .having(
                    (s) => s.errorMessage.toLowerCase(),
                    'errorMessage contains memory limit/bounds',
                    contains('memory'),
                  ),
            ),
          );

          await sessionBloc.close();
        },
      );
    },
  );
}
