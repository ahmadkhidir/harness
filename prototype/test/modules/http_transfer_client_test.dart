import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/transfer/http_transfer_client.dart';
import 'package:harness/modules/transfer/transfer_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Captures the outgoing request before it is finalized.
class _RecordingClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    lastRequest = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('HttpTransferClient - FEAT-009', () {
    test('sends requests to allowlisted hosts and returns the response',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://api.example.com/status');
        return http.Response('{"ok":true}', 200, headers: {
          'content-type': 'application/json',
          'x-trace': 'abc',
        });
      });

      final result = await HttpTransferClient(client: client).send(
        method: 'GET',
        url: Uri.parse('https://api.example.com/status'),
        allowedHosts: const ['api.example.com'],
      );

      expect(result.status, 200);
      expect(result.body, '{"ok":true}');
      expect(result.truncated, isFalse);
      expect(result.headers['x-trace'], 'abc');
    });

    test('refuses hosts that are not on the allowlist without sending',
        () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('', 200);
      });

      await expectLater(
        () => HttpTransferClient(client: client).send(
          method: 'POST',
          url: Uri.parse('https://evil.example/collect'),
          allowedHosts: const ['api.example.com'],
        ),
        throwsA(isA<TransferException>().having(
          (e) => e.message,
          'message',
          contains('not on the allowed hosts list'),
        )),
      );
      expect(requests, 0);
    });

    test('supports host:port allowlist entries', () async {
      final client = MockClient((request) async => http.Response('ok', 200));

      final result = await HttpTransferClient(client: client).send(
        method: 'GET',
        url: Uri.parse('https://api.example.com:8443/health'),
        allowedHosts: const ['api.example.com:8443'],
      );

      expect(result.status, 200);
    });

    test('serializes JSON bodies with a JSON content type', () async {
      final client = MockClient((request) async {
        final contentType = request.headers.entries
            .firstWhere(
              (entry) => entry.key.toLowerCase() == 'content-type',
              orElse: () => const MapEntry('', ''),
            )
            .value;
        expect(contentType, contains('application/json'));
        expect(json.decode(request.body), {'title': 'Weekly'});
        return http.Response('created', 201);
      });

      final result = await HttpTransferClient(client: client).send(
        method: 'POST',
        url: Uri.parse('https://api.example.com/reports'),
        allowedHosts: const ['api.example.com'],
        jsonBody: const {'title': 'Weekly'},
      );

      expect(result.status, 201);
    });

    test('truncates response bodies at the configured cap', () async {
      final client = MockClient(
        (request) async => http.Response('0123456789', 200),
      );

      final result = await HttpTransferClient(
        client: client,
        maxResponseBytes: 5,
      ).send(
        method: 'GET',
        url: Uri.parse('https://api.example.com/large'),
        allowedHosts: const ['api.example.com'],
      );

      expect(result.body, '01234');
      expect(result.truncated, isTrue);
    });

    test('does not follow redirects that could bypass the allowlist',
        () async {
      final client = MockClient(
        (request) async => http.Response('', 302, headers: {
          'location': 'https://evil.example/target',
        }),
      );

      await expectLater(
        () => HttpTransferClient(client: client).send(
          method: 'GET',
          url: Uri.parse('https://api.example.com/go'),
          allowedHosts: const ['api.example.com'],
        ),
        throwsA(isA<TransferException>().having(
          (e) => e.message,
          'message',
          contains('redirect'),
        )),
      );
    });

    test('rejects private hosts regardless of the allowlist', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('', 200);
      });

      await expectLater(
        () => HttpTransferClient(client: client).send(
          method: 'GET',
          url: Uri.parse('http://192.168.1.5/admin'),
          allowedHosts: const ['192.168.1.5'],
        ),
        throwsA(isA<TransferException>()),
      );
      expect(requests, 0);
    });

    test('uploads a stored file as multipart content', () async {
      final tempDir = await Directory.systemTemp.createTemp('harness_upload_');
      addTearDown(() => tempDir.delete(recursive: true));
      final upload = File('${tempDir.path}/report.txt');
      await upload.writeAsString('hello upload');

      final client = _RecordingClient();
      final result = await HttpTransferClient(client: client).send(
        method: 'POST',
        url: Uri.parse('https://api.example.com/upload'),
        allowedHosts: const ['api.example.com'],
        jsonBody: const {'title': 'Weekly'},
        uploadFile: upload,
      );

      final request = client.lastRequest;
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['json'], contains('Weekly'));
      expect(multipart.files, hasLength(1));
      expect(multipart.files.single.field, 'file');
      expect(result.status, 200);
    });
  });
}
