import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/modules/transfer/transfer_module.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HarnessFileSystem fileSystem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_transfer_');
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
  }) {
    return TransferModule(
      allowedHostsProvider: () async => allowedHosts,
      fileSystemProvider: () => fileSystem,
      client: client,
    );
  }

  group('TransferModule - FEAT-009', () {
    test('download_media returns the resolved storage, path, MIME, and size',
        () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode('png-bytes'),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );

      final response = await buildModule(client: client).executeCommand(
        'download_media',
        {'url': 'https://example.com/trip.png'},
      );

      expect(response.isSuccess, isTrue);
      final data = response.data as Map<String, dynamic>;
      expect(data['storage'], 'primary');
      expect(data['path'], 'trip.png');
      expect(data['mimeType'], 'image/png');
      expect(data['byteSize'], 'png-bytes'.length);
    });

    test('download_media rejects unknown storage volumes', () async {
      final response = await buildModule().executeCommand('download_media', {
        'url': 'https://example.com/trip.png',
        'storage': 'missing',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Unknown storage volume'));
    });

    test('http_request blocks when no allowed hosts are configured', () async {
      final response = await buildModule(allowedHosts: const [])
          .executeCommand('http_request', {
        'method': 'GET',
        'url': 'https://api.example.com/status',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('No allowed hosts'));
    });

    test('http_request blocks unlisted hosts', () async {
      final response = await buildModule().executeCommand('http_request', {
        'method': 'GET',
        'url': 'https://evil.example/status',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('not on the allowed hosts list'));
    });

    test('http_request returns status, headers, and body', () async {
      final client = MockClient(
        (request) async => http.Response('{"ok":true}', 200, headers: {
          'content-type': 'application/json',
        }),
      );

      final response = await buildModule(client: client).executeCommand(
        'http_request',
        {
          'method': 'GET',
          'url': 'https://api.example.com/status',
        },
      );

      expect(response.isSuccess, isTrue);
      final data = response.data as Map<String, dynamic>;
      expect(data['status'], 200);
      expect(data['body'], '{"ok":true}');
      expect(data['truncated'], isFalse);
    });

    test('http_request rejects unsupported methods', () async {
      final response = await buildModule().executeCommand('http_request', {
        'method': 'TRACE',
        'url': 'https://api.example.com/status',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('method'));
    });

    test('http_request rejects body and json together', () async {
      final response = await buildModule().executeCommand('http_request', {
        'method': 'POST',
        'url': 'https://api.example.com/status',
        'body': 'raw',
        'json': {'a': 1},
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('mutually exclusive'));
    });

    test('http_request reports missing upload files', () async {
      final response = await buildModule().executeCommand('http_request', {
        'method': 'POST',
        'url': 'https://api.example.com/upload',
        'filePath': 'primary/missing.txt',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('does not exist'));
    });
  });
}
