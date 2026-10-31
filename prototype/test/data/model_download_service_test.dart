import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:harness/core/models/on_device_model_spec.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/services/model_download_service.dart';

void main() {
  late Directory tempDir;
  late HarnessFileSystem fs;

  const testSpec = OnDeviceModelSpec(
    id: 'test_model',
    name: 'Test Model',
    parameterSize: '1.0B',
    format: 'Q4_K_M.gguf',
    memoryUsageMb: 800,
    downloadSize: '100 MB',
    description: 'Test on-device model spec',
    fileName: 'test-model.gguf',
    downloadUrl: 'https://example.com/models/test-model.gguf',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_download_test_');
    fs = await HarnessFileSystem.init(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Fresh download writes to .part file and renames to target on completion', () async {
    final payload = List<int>.generate(1024, (i) => i % 256);

    final mockClient = MockClient.streaming((request, bodyStream) async {
      expect(request.headers.containsKey('Range'), isFalse);
      return http.StreamedResponse(
        Stream.value(payload),
        200,
        contentLength: payload.length,
      );
    });

    final service = ModelDownloadService(
      fileSystem: fs,
      httpClient: mockClient,
      isSimulation: false,
    );

    expect(service.isDownloaded(testSpec), isFalse);
    expect(service.hasPartialDownload(testSpec), isFalse);

    final progressList = <double>[];
    await for (final progress in service.downloadModel(testSpec)) {
      progressList.add(progress);
    }

    expect(progressList.last, 1.0);
    expect(service.isDownloaded(testSpec), isTrue);
    expect(service.hasPartialDownload(testSpec), isFalse);

    final finalFile = fs.modelFile(testSpec.fileName);
    final partFile = fs.modelPartFile(testSpec.fileName);

    expect(await finalFile.exists(), isTrue);
    expect(await partFile.exists(), isFalse);
    expect(await finalFile.length(), payload.length);
  });

  test('Download error preserves .part file on disk and does NOT delete it', () async {
    final firstChunk = List<int>.generate(512, (i) => i % 256);

    final mockClient = MockClient.streaming((request, bodyStream) async {
      final controller = StreamController<List<int>>();
      controller.add(firstChunk);
      // Simulate network socket drop / timeout
      controller.addError(const SocketException('Connection reset by peer'));
      controller.close();

      return http.StreamedResponse(
        controller.stream,
        200,
        contentLength: 1024,
      );
    });

    final service = ModelDownloadService(
      fileSystem: fs,
      httpClient: mockClient,
      isSimulation: false,
    );

    await expectLater(
      service.downloadModel(testSpec),
      emitsThrough(
        emitsError(
          isA<String>().having(
            (e) => e,
            'message',
            contains('Connection reset'),
          ),
        ),
      ),
    );

    // Wait a brief moment for the stream error handler to finish flushing
    await Future.delayed(const Duration(milliseconds: 100));

    final partFile = fs.modelPartFile(testSpec.fileName);
    final finalFile = fs.modelFile(testSpec.fileName);

    expect(await finalFile.exists(), isFalse);
    expect(await partFile.exists(), isTrue);
    expect(await partFile.length(), firstChunk.length);
    expect(service.hasPartialDownload(testSpec), isTrue);
    expect(service.getPartialDownloadedBytes(testSpec), firstChunk.length);
  });

  test('Resuming download sends HTTP Range header and appends to .part file', () async {
    final firstChunk = List<int>.generate(500, (i) => 1);
    final secondChunk = List<int>.generate(500, (i) => 2);
    const totalBytes = 1000;

    // Simulate existing .part file from interrupted download
    final partFile = fs.modelPartFile(testSpec.fileName);
    await partFile.parent.create(recursive: true);
    await partFile.writeAsBytes(firstChunk);

    final mockClient = MockClient.streaming((request, bodyStream) async {
      // Must include Range: bytes=500-
      expect(request.headers['Range'], 'bytes=500-');
      return http.StreamedResponse(
        Stream.value(secondChunk),
        206, // Partial Content
        contentLength: secondChunk.length,
        headers: {
          'content-range': 'bytes 500-999/$totalBytes',
        },
      );
    });

    final service = ModelDownloadService(
      fileSystem: fs,
      httpClient: mockClient,
      isSimulation: false,
    );

    expect(service.hasPartialDownload(testSpec), isTrue);
    expect(service.getPartialDownloadedBytes(testSpec), 500);

    final progressList = <double>[];
    await for (final progress in service.downloadModel(testSpec)) {
      progressList.add(progress);
    }

    expect(progressList.last, 1.0);
    expect(service.isDownloaded(testSpec), isTrue);
    expect(service.hasPartialDownload(testSpec), isFalse);

    final finalFile = fs.modelFile(testSpec.fileName);
    expect(await finalFile.exists(), isTrue);
    expect(await finalFile.length(), totalBytes);

    // Verify file contents were appended seamlessly
    final bytes = await finalFile.readAsBytes();
    expect(bytes.sublist(0, 500), firstChunk);
    expect(bytes.sublist(500, 1000), secondChunk);
  });

  test('cancelAndClearDownload discards .part file', () async {
    final partFile = fs.modelPartFile(testSpec.fileName);
    await partFile.parent.create(recursive: true);
    await partFile.writeAsBytes([1, 2, 3, 4]);

    final service = ModelDownloadService(
      fileSystem: fs,
      isSimulation: false,
    );

    expect(service.hasPartialDownload(testSpec), isTrue);

    await service.cancelAndClearDownload(testSpec);

    expect(service.hasPartialDownload(testSpec), isFalse);
    expect(await partFile.exists(), isFalse);
  });

  test('deleteDownloadedModel deletes both completed model and residual part files', () async {
    final finalFile = fs.modelFile(testSpec.fileName);
    final partFile = fs.modelPartFile(testSpec.fileName);
    await finalFile.parent.create(recursive: true);
    await finalFile.writeAsString('{"status": "verified_local"}');
    await partFile.writeAsBytes([1, 2, 3]);

    final service = ModelDownloadService(
      fileSystem: fs,
      isSimulation: true,
    );

    expect(service.isDownloaded(testSpec), isTrue);

    await service.deleteDownloadedModel(testSpec);

    expect(service.isDownloaded(testSpec), isFalse);
    expect(await finalFile.exists(), isFalse);
    expect(await partFile.exists(), isFalse);
  });

  test('Dynamic filesystem resolution writes to newly selected filesystem root', () async {
    final secondTempDir = await Directory.systemTemp.createTemp('second_fs_');
    try {
      final defaultService = ModelDownloadService(isSimulation: true);

      // Initially targeting fs (tempDir)
      final initialPart = await defaultService.resolveModelPartFileAsync(testSpec.fileName);
      expect(initialPart.path.startsWith(tempDir.path), isTrue);

      // Switch filesystem root
      final newFs = await HarnessFileSystem.init(secondTempDir);
      expect(HarnessFileSystem.instance, newFs);

      // Now defaultService automatically points to new root without re-instantiation!
      final newPart = await defaultService.resolveModelPartFileAsync(testSpec.fileName);
      expect(newPart.path.startsWith(secondTempDir.path), isTrue);
    } finally {
      if (await secondTempDir.exists()) {
        await secondTempDir.delete(recursive: true);
      }
    }
  });
}
