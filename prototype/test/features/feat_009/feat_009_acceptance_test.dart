import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/engine/context_builder.dart';
import 'package:harness/core/engine/engine_events.dart';
import 'package:harness/core/engine/harness_engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/modules/transfer/transfer_module.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

class _ScriptedProvider extends ModelProvider {
  final List<String> script;
  int _index = 0;

  _ScriptedProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'scripted_transfer',
        providerType: 'gemini',
        displayName: 'Scripted Transfer Model',
        modelName: 'scripted-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    if (_index < script.length) return script[_index++];
    return script.last;
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fileSystem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_feat009_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
  });

  tearDown(() async {
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TransferModule buildModule({
    List<String> allowedHosts = const ['api.example.com'],
    http.Client? client,
    int maxResponseBytes = 1000000,
  }) {
    return TransferModule(
      allowedHostsProvider: () async => allowedHosts,
      fileSystemProvider: () => fileSystem,
      client: client,
      maxResponseBytes: maxResponseBytes,
    );
  }

  group('FEAT-009 Acceptance Tests - Network Transfer & Media Ingestion', () {
    test('Criterion 1: download_media stores the file at the root of primary',
        () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode('image-bytes'),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );

      final router = CommandRouter()
        ..registerModule(buildModule(client: client));

      final provider = _ScriptedProvider([
        '<system_call>{"command": "download_media", "parameters": {"url": "https://example.com/photos/trip.png"}}</system_call>',
        '<system_call>{"command": "send_message", "parameters": {"text": "Saved the photo."}}</system_call>',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: ContextBuilder(),
        modelProvider: provider,
      );

      final events = await engine
          .executeTurn(
            userPrompt: 'Save that photo for me.',
            sessionId: 'sess_download',
          )
          .toList();

      final finished = events.firstWhere(
        (event) =>
            event is EngineSystemCallFinished &&
            event.call.command == 'download_media',
      ) as EngineSystemCallFinished;

      expect(finished.response.isSuccess, isTrue);
      final data = finished.response.data as Map<String, dynamic>;
      expect(data['storage'], 'primary');
      expect(data['path'], 'trip.png');
      expect(data['mimeType'], 'image/png');

      expect(
        await File(p.join(fileSystem.storageDir.path, 'trip.png')).exists(),
        isTrue,
      );
    });

    test('Criterion 2: download_media honors a registered volume and path',
        () async {
      final mountDir = Directory(p.join(tempDir.path, 'mounted'));
      await mountDir.create(recursive: true);
      fileSystem.mounts.registerMount('docs', mountDir);

      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode('pdf-bytes'),
          200,
          headers: {'content-type': 'application/pdf'},
        ),
      );

      final response = await buildModule(client: client).executeCommand(
        'download_media',
        {
          'url': 'https://example.com/report.pdf',
          'storage': 'docs',
          'path': 'projects/acme/report.pdf',
        },
      );

      expect(response.isSuccess, isTrue);
      final data = response.data as Map<String, dynamic>;
      expect(data['storage'], 'docs');
      expect(data['path'], 'projects/acme/report.pdf');
      expect(
        await File(p.join(mountDir.path, 'projects/acme/report.pdf')).exists(),
        isTrue,
      );
    });

    test('Criterion 3: http_request returns status, headers, and body',
        () async {
      final client = MockClient(
        (request) async => http.Response('{"id":7}', 201, headers: {
          'content-type': 'application/json',
          'x-request-id': 'req-7',
        }),
      );

      final response = await buildModule(client: client).executeCommand(
        'http_request',
        {
          'method': 'POST',
          'url': 'https://api.example.com/reports',
          'json': {'title': 'Weekly'},
        },
      );

      expect(response.isSuccess, isTrue);
      final data = response.data as Map<String, dynamic>;
      expect(data['status'], 201);
      expect(data['body'], '{"id":7}');
      expect((data['headers'] as Map)['x-request-id'], 'req-7');
    });

    test('Edge Case: unlisted hosts are refused without a request', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('', 200);
      });

      final response = await buildModule(client: client).executeCommand(
        'http_request',
        {
          'method': 'GET',
          'url': 'https://evil.example/collect',
        },
      );

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('not on the allowed hosts list'));
      expect(requests, 0);
    });

    test('Edge Case: existing files are never overwritten', () async {
      final existing = File(p.join(fileSystem.storageDir.path, 'trip.png'));
      await existing.writeAsString('old');

      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode('new'),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );

      final response = await buildModule(client: client).executeCommand(
        'download_media',
        {'url': 'https://example.com/photos/trip.png'},
      );

      expect(response.isSuccess, isTrue);
      expect((response.data as Map<String, dynamic>)['path'], 'trip-1.png');
      expect(await existing.readAsString(), 'old');
    });

    test('Edge Case: oversized http_request bodies are truncated at 1 MB',
        () async {
      final client = MockClient(
        (request) async => http.Response('x' * 20, 200),
      );

      final response = await buildModule(
        client: client,
        maxResponseBytes: 5,
      ).executeCommand(
        'http_request',
        {
          'method': 'GET',
          'url': 'https://api.example.com/large',
        },
      );

      expect(response.isSuccess, isTrue);
      final data = response.data as Map<String, dynamic>;
      expect(data['truncated'], isTrue);
      expect((data['body'] as String).length, 5);
    });
  });
}
