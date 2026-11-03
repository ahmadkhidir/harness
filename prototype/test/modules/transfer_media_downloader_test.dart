import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/modules/transfer/media_downloader.dart';
import 'package:harness/modules/transfer/transfer_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

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

  MediaDownloader buildDownloader(
    http.Client client, {
    int maxBytes = 25 * 1024 * 1024,
  }) {
    return MediaDownloader(
      fileSystemProvider: () => fileSystem,
      client: client,
      maxBytes: maxBytes,
      timeout: const Duration(seconds: 5),
    );
  }

  http.Response mediaResponse(
    String body, {
    String contentType = 'image/png',
    Map<String, String> headers = const {},
  }) {
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': contentType, ...headers},
    );
  }

  group('MediaDownloader - FEAT-009', () {
    test('downloads into the root of primary by default', () async {
      final client = MockClient((request) async => mediaResponse('png-bytes'));
      final result = await buildDownloader(client).download(
        url: 'https://example.com/photos/trip.png',
      );

      expect(result.storage, 'primary');
      expect(result.path, 'trip.png');
      expect(result.mimeType, 'image/png');
      expect(result.byteSize, 'png-bytes'.length);

      final file = File(p.join(fileSystem.storageDir.path, 'trip.png'));
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'png-bytes');
    });

    test('writes into a registered external mount and relative path', () async {
      final mountDir = Directory(p.join(tempDir.path, 'mounted'));
      await mountDir.create(recursive: true);
      fileSystem.mounts.registerMount('docs', mountDir);

      final client = MockClient((request) async => mediaResponse('pdf-bytes'));
      final result = await buildDownloader(client).download(
        url: 'https://example.com/report.pdf',
        storage: 'docs',
        path: 'projects/acme/cover.pdf',
      );

      expect(result.storage, 'docs');
      expect(result.path, 'projects/acme/cover.pdf');

      final file = File(p.join(mountDir.path, 'projects/acme/cover.pdf'));
      expect(await file.exists(), isTrue);
    });

    test('uses Content-Disposition filenames when no destination is named',
        () async {
      final client = MockClient(
        (request) async => mediaResponse(
          'cover',
          headers: {
            'content-disposition': 'attachment; filename="cover-art.png"',
          },
        ),
      );

      final result = await buildDownloader(client).download(
        url: 'https://example.com/download?id=42',
      );

      expect(result.path, 'cover-art.png');
      expect(
        await File(p.join(fileSystem.storageDir.path, 'cover-art.png')).exists(),
        isTrue,
      );
    });

    test('never overwrites an existing destination', () async {
      final existing = File(p.join(fileSystem.storageDir.path, 'trip.png'));
      await existing.writeAsString('old');

      final client = MockClient((request) async => mediaResponse('new'));
      final result = await buildDownloader(client).download(
        url: 'https://example.com/photos/trip.png',
      );

      expect(result.path, 'trip-1.png');
      expect(await existing.readAsString(), 'old');
      expect(
        await File(p.join(fileSystem.storageDir.path, 'trip-1.png'))
            .readAsString(),
        'new',
      );
    });

    test('generates a timestamped name when the URL has no usable segment',
        () async {
      final client = MockClient((request) async => mediaResponse('bytes'));
      final result = await buildDownloader(client).download(
        url: 'https://example.com/',
      );

      expect(p.basename(result.path), startsWith('download_'));
      expect(result.path, endsWith('.png'));
    });

    test('rejects unsupported media types without writing a file', () async {
      final client = MockClient(
        (request) async => mediaResponse('html', contentType: 'text/html'),
      );

      await expectLater(
        () => buildDownloader(client).download(
          url: 'https://example.com/page.html',
        ),
        throwsA(isA<TransferException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported media type'),
        )),
      );

      expect(await fileSystem.storageDir.list().toList(), isEmpty);
    });

    test('aborts oversized downloads and removes partial files', () async {
      final client = MockClient(
        (request) async => mediaResponse('0123456789'),
      );

      await expectLater(
        () => buildDownloader(client, maxBytes: 4).download(
          url: 'https://example.com/big.png',
        ),
        throwsA(isA<TransferException>().having(
          (e) => e.message,
          'message',
          contains('download limit'),
        )),
      );

      expect(await fileSystem.storageDir.list().toList(), isEmpty);
    });

    test('rejects private hosts before making a request', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return mediaResponse('bytes');
      });

      await expectLater(
        () => buildDownloader(client).download(
          url: 'http://127.0.0.1/secret.png',
        ),
        throwsA(isA<TransferException>()),
      );
      expect(requests, 0);
    });

    test('rejects paths that escape the selected storage volume', () async {
      final client = MockClient((request) async => mediaResponse('bytes'));

      await expectLater(
        () => buildDownloader(client).download(
          url: 'https://example.com/trip.png',
          path: '../escape.png',
        ),
        throwsA(isA<TransferException>()),
      );
      expect(await File(p.join(tempDir.path, 'escape.png')).exists(), isFalse);
    });
  });
}
