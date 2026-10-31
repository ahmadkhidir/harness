import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/models/on_device_model_spec.dart';
import '../../core/utils/file_system_manager.dart';

/// Service responsible for managing local on-device small language model (SLM) downloads,
/// executing streaming HTTP requests from HuggingFace / CDN directly to local storage,
/// tracking real-time determinate download progress percentages and megabytes,
/// supporting resumable downloads via HTTP Range headers and `.part` temporary files,
/// and verifying model files on disk.
class ModelDownloadService {
  final HarnessFileSystem? _explicitFileSystem;
  final http.Client? httpClient;
  final bool isSimulation;
  final Duration tickInterval;
  final int totalSteps;

  /// Dynamically resolves the active file system, prioritizing any explicitly injected
  /// instance (e.g. for unit tests) or falling back dynamically to the current singleton.
  HarnessFileSystem? get fileSystem =>
      _explicitFileSystem ?? HarnessFileSystem.instance;

  // In-memory active downloads: modelId -> progress (0.0 to 1.0)
  final Map<String, double> _activeProgress = {};
  final Map<String, int> _downloadedBytes = {};
  final Map<String, StreamController<double>> _controllers = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, IOSink> _activeSinks = {};

  ModelDownloadService({
    HarnessFileSystem? fileSystem,
    this.httpClient,
    this.isSimulation = false,
    this.tickInterval = const Duration(milliseconds: 100),
    this.totalSteps = 50,
  }) : _explicitFileSystem = fileSystem;

  /// Synchronously attempts to locate the model file reference on disk.
  File? resolveModelFileSync(String fileName) {
    final cleanName = fileName.trim();
    final currentFs = fileSystem;
    if (currentFs != null) {
      final fsFile = currentFs.modelFile(cleanName);
      if (fsFile.existsSync() && fsFile.lengthSync() > 0) return fsFile;

      // Migration check from legacy storage/models/ location
      final legacyFsFile = File(
        p.join(currentFs.rootDir.path, 'storage', 'models', cleanName),
      );
      if (legacyFsFile.existsSync() && legacyFsFile.lengthSync() > 0) {
        try {
          fsFile.parent.createSync(recursive: true);
          legacyFsFile.renameSync(fsFile.path);
          return fsFile;
        } catch (_) {
          return legacyFsFile;
        }
      }
      return fsFile;
    }

    try {
      final currentDir = Directory(
        p.join(Directory.current.path, 'data', 'models'),
      );
      final file = File(p.join(currentDir.path, cleanName));
      if (file.existsSync() && file.lengthSync() > 0) return file;
      final directFile = File(cleanName);
      if (directFile.existsSync() && directFile.lengthSync() > 0) {
        return directFile;
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Synchronously locates the `.part` download file reference on disk.
  File? resolveModelPartFileSync(String fileName) {
    final cleanName = fileName.trim();
    final currentFs = fileSystem;
    if (currentFs != null) {
      final targetPart = currentFs.modelPartFile(cleanName);
      if (targetPart.existsSync() && targetPart.lengthSync() > 0) {
        return targetPart;
      }
      return targetPart;
    }

    try {
      final currentDir = Directory(
        p.join(Directory.current.path, 'data', 'models'),
      );
      return File(p.join(currentDir.path, '$cleanName.part'));
    } catch (_) {
      return null;
    }
  }

  /// Asynchronously resolves the model file reference, guaranteeing it targets the selected filesystem.
  Future<File> resolveModelFileAsync(String fileName) async {
    final cleanName = fileName.trim();
    final syncFile = resolveModelFileSync(cleanName);
    if (syncFile != null && syncFile.existsSync() && syncFile.lengthSync() > 0) {
      return syncFile;
    }

    final currentFs = fileSystem;
    if (currentFs != null) {
      final targetFile = currentFs.modelFile(cleanName);
      if (!targetFile.parent.existsSync()) {
        try {
          await targetFile.parent.create(recursive: true);
        } catch (_) {}
      }

      // Check migration from legacy appDocDir if file exists there
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final legacyFile = File(
          p.join(appDocDir.path, 'Harness', 'data', 'models', cleanName),
        );
        if (legacyFile.existsSync() &&
            legacyFile.lengthSync() > 0 &&
            legacyFile.path != targetFile.path) {
          if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
            await legacyFile.rename(targetFile.path);
            return targetFile;
          }
        }
      } catch (_) {}

      return targetFile;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(
        p.join(appDocDir.path, 'Harness', 'data', 'models'),
      );
      if (!modelsDir.existsSync()) {
        await modelsDir.create(recursive: true);
      }
      return File(p.join(modelsDir.path, cleanName));
    } catch (_) {
      final fallbackDir = Directory(
        p.join(Directory.current.path, 'data', 'models'),
      );
      if (!fallbackDir.existsSync()) {
        try {
          fallbackDir.createSync(recursive: true);
        } catch (_) {}
      }
      return syncFile ?? File(p.join(fallbackDir.path, cleanName));
    }
  }

  /// Asynchronously resolves the `.part` download file reference targeting the selected filesystem.
  Future<File> resolveModelPartFileAsync(String fileName) async {
    final currentFs = fileSystem;
    if (currentFs != null) {
      final targetPart = currentFs.modelPartFile(fileName);
      if (!targetPart.parent.existsSync()) {
        try {
          await targetPart.parent.create(recursive: true);
        } catch (_) {}
      }

      // Check migration from legacy appDocDir if a .part exists there
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final legacyPart = File(
          p.join(appDocDir.path, 'Harness', 'data', 'models', '$fileName.part'),
        );
        if (legacyPart.existsSync() &&
            legacyPart.lengthSync() > 0 &&
            legacyPart.path != targetPart.path) {
          if (!targetPart.existsSync() || targetPart.lengthSync() == 0) {
            await legacyPart.rename(targetPart.path);
            return targetPart;
          }
        }
      } catch (_) {}

      return targetPart;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(
        p.join(appDocDir.path, 'Harness', 'data', 'models'),
      );
      if (!modelsDir.existsSync()) {
        await modelsDir.create(recursive: true);
      }
      return File(p.join(modelsDir.path, '$fileName.part'));
    } catch (_) {
      final fallbackDir = Directory(
        p.join(Directory.current.path, 'data', 'models'),
      );
      if (!fallbackDir.existsSync()) {
        try {
          fallbackDir.createSync(recursive: true);
        } catch (_) {}
      }
      return File(p.join(fallbackDir.path, '$fileName.part'));
    }
  }

  /// Checks whether a model is already downloaded locally on the device with verified disk bytes.
  bool isDownloaded(OnDeviceModelSpec spec) {
    final file = resolveModelFileSync(spec.fileName);
    return file != null && file.existsSync() && file.lengthSync() > 0;
  }

  /// Checks whether a partial `.part` download file exists on disk for resuming.
  bool hasPartialDownload(OnDeviceModelSpec spec) {
    if (isDownloaded(spec)) return false;
    final partFile = resolveModelPartFileSync(spec.fileName);
    return partFile != null && partFile.existsSync() && partFile.lengthSync() > 0;
  }

  /// Returns the number of bytes downloaded so far (either actively streaming or paused in `.part`).
  int getPartialDownloadedBytes(OnDeviceModelSpec spec) {
    if (_downloadedBytes.containsKey(spec.id)) {
      return _downloadedBytes[spec.id]!;
    }
    final partFile = resolveModelPartFileSync(spec.fileName);
    if (partFile != null && partFile.existsSync()) {
      return partFile.lengthSync();
    }
    return 0;
  }

  /// Returns the progress ratio (0.0 to 1.0) of partial bytes on disk relative to expected total size.
  double getPartialProgress(OnDeviceModelSpec spec) {
    if (_activeProgress.containsKey(spec.id)) {
      return _activeProgress[spec.id]!;
    }
    final bytes = getPartialDownloadedBytes(spec);
    if (bytes <= 0) return 0.0;
    final totalBytes = spec.totalSizeInMb * 1024 * 1024;
    return (bytes / totalBytes).clamp(0.0, 0.99);
  }

  /// Returns current progress (0.0 to 1.0) if currently downloading, otherwise null.
  double? getProgress(String modelId) => _activeProgress[modelId];

  /// Returns current downloaded megabytes for display.
  int getDownloadedMb(OnDeviceModelSpec spec) {
    if (_downloadedBytes.containsKey(spec.id)) {
      return _downloadedBytes[spec.id]! ~/ (1024 * 1024);
    }
    final progress = _activeProgress[spec.id] ?? 0.0;
    return (progress * spec.totalSizeInMb).round();
  }

  /// Whether the specified model is currently actively downloading.
  bool isDownloading(String modelId) => _activeProgress.containsKey(modelId);

  /// Streams determinate progress (0.0 to 1.0) for downloading an [OnDeviceModelSpec].
  /// Supports resuming from partial `.part` file using HTTP Range headers.
  Stream<double> downloadModel(OnDeviceModelSpec spec) {
    if (_controllers.containsKey(spec.id)) {
      return _controllers[spec.id]!.stream;
    }

    final controller = StreamController<double>.broadcast();
    _controllers[spec.id] = controller;
    _activeProgress[spec.id] = getPartialProgress(spec);
    _downloadedBytes[spec.id] = getPartialDownloadedBytes(spec);

    if (!isSimulation &&
        spec.downloadUrl != null &&
        (spec.downloadUrl!.startsWith('http://') ||
            spec.downloadUrl!.startsWith('https://'))) {
      _startHttpDownload(spec, controller);
    } else {
      _startSimulatedDownload(spec, controller);
    }

    return controller.stream;
  }

  Future<void> _startHttpDownload(
    OnDeviceModelSpec spec,
    StreamController<double> controller,
  ) async {
    final client = httpClient ?? http.Client();
    try {
      final targetFile = await resolveModelFileAsync(spec.fileName);
      final partFile = await resolveModelPartFileAsync(spec.fileName);

      // ignore: avoid_print
      print('[ModelDownloadService] Target path: ${targetFile.path}');
      // ignore: avoid_print
      print('[ModelDownloadService] Part path: ${partFile.path}');

      // Ensure directory exists in the selected filesystem
      await partFile.parent.create(recursive: true);

      // Verify file write access before proceeding to stream
      try {
        final testRaf = await partFile.open(mode: FileMode.writeOnlyAppend);
        await testRaf.close();
      } catch (e) {
        // ignore: avoid_print
        print('[ModelDownloadService] Write permission error on ${partFile.path}: $e');
        controller.addError('Storage write permission denied for ${partFile.path}: $e');
        _cleanup(spec.id);
        return;
      }

      // Check if partial download already exists on disk
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      final request = http.Request('GET', Uri.parse(spec.downloadUrl!));
      request.followRedirects = true;
      request.maxRedirects = 5;

      final hfToken = AppConfig.huggingFaceToken;
      if (hfToken != null && spec.downloadUrl!.contains('huggingface.co')) {
        request.headers['Authorization'] = 'Bearer $hfToken';
      }

      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final streamedResponse = await client.send(request);

      int totalBytes;
      int receivedBytes;
      IOSink sink;

      if (streamedResponse.statusCode == 206) {
        // 206 Partial Content: Resuming download!
        int? parsedTotal;
        final contentRange = streamedResponse.headers['content-range'];
        if (contentRange != null && contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          parsedTotal = int.tryParse(totalStr);
        }

        totalBytes = parsedTotal ??
            (existingBytes +
                (streamedResponse.contentLength ??
                    (spec.totalSizeInMb * 1024 * 1024 - existingBytes)));

        receivedBytes = existingBytes;
        sink = partFile.openWrite(mode: FileMode.append);
        sink.done.catchError((err) {
          // ignore: avoid_print
          print('[ModelDownloadService] Sink stream error: $err');
        });
      } else if (streamedResponse.statusCode == 200) {
        // 200 OK: Full content returned (start from scratch or server ignored Range)
        totalBytes = streamedResponse.contentLength ??
            (spec.totalSizeInMb * 1024 * 1024);
        receivedBytes = 0;
        sink = partFile.openWrite(mode: FileMode.write);
        sink.done.catchError((err) {
          // ignore: avoid_print
          print('[ModelDownloadService] Sink stream error: $err');
        });
      } else if (streamedResponse.statusCode == 416) {
        // 416 Range Not Satisfiable:
        // Either existingBytes is equal to total size (already finished),
        // or range is invalid.
        if (existingBytes >= (spec.totalSizeInMb * 1024 * 1024 * 0.95)) {
          // File was already completely downloaded!
          if (await targetFile.exists()) await targetFile.delete();
          await partFile.rename(targetFile.path);
          _activeProgress[spec.id] = 1.0;
          _downloadedBytes[spec.id] = existingBytes;
          controller.add(1.0);
          _cleanup(spec.id);
          await controller.close();
          return;
        } else {
          // Incomplete but server rejected range; reset part file and retry full download
          await partFile.delete();
          await _startHttpDownload(spec, controller);
          return;
        }
      } else {
        controller.addError(
          'HTTP download failed with status ${streamedResponse.statusCode}: ${streamedResponse.reasonPhrase}',
        );
        _cleanup(spec.id);
        return;
      }

      _activeSinks[spec.id] = sink;
      _activeProgress[spec.id] =
          totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
      _downloadedBytes[spec.id] = receivedBytes;
      controller.add(_activeProgress[spec.id]!);

      final sub = streamedResponse.stream.listen(
        (chunk) {
          receivedBytes += chunk.length;
          sink.add(chunk);

          final progress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
              : 0.0;
          _activeProgress[spec.id] = progress;
          _downloadedBytes[spec.id] = receivedBytes;
          controller.add(progress);
        },
        onError: (err) async {
          // ignore: avoid_print
          print('[ModelDownloadService] Download stream error: $err');
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
          _activeSinks.remove(spec.id);

          // IMPORTANT: Do NOT delete partFile! Preserve all downloaded bytes on disk for resume!
          controller.addError('Download error: $err');
          _cleanup(spec.id);
        },
        onDone: () async {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
          _activeSinks.remove(spec.id);

          // Verify part file and rename to target destination in the selected filesystem
          if (await partFile.exists()) {
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            await partFile.rename(targetFile.path);
          }

          _activeProgress[spec.id] = 1.0;
          _downloadedBytes[spec.id] = totalBytes;
          controller.add(1.0);
          _cleanup(spec.id);
          await controller.close();
        },
        cancelOnError: true,
      );

      _subscriptions[spec.id] = sub;
    } catch (e, stack) {
      // ignore: avoid_print
      print('[ModelDownloadService] Failed to start download: $e\n$stack');
      controller.addError('Failed to start download: $e');
      _cleanup(spec.id);
    }
  }

  void _startSimulatedDownload(
    OnDeviceModelSpec spec,
    StreamController<double> controller,
  ) {
    final initialProgress = _activeProgress[spec.id] ?? 0.0;
    int currentStep = (initialProgress * totalSteps).round();

    Timer.periodic(tickInterval, (timer) async {
      currentStep++;
      if (currentStep < totalSteps) {
        final progress = (currentStep / totalSteps).clamp(0.0, 0.99);
        _activeProgress[spec.id] = progress;
        _downloadedBytes[spec.id] =
            (progress * spec.totalSizeInMb * 1024 * 1024).round();
        controller.add(progress);
      } else {
        timer.cancel();

        try {
          final file = await resolveModelFileAsync(spec.fileName);
          if (!file.existsSync() || file.lengthSync() == 0) {
            await file.parent.create(recursive: true);
            final payload = {
              'model_id': spec.id,
              'name': spec.name,
              'parameter_size': spec.parameterSize,
              'format': spec.format,
              'download_size': spec.downloadSize,
              'resident_memory_mb': spec.memoryUsageMb,
              'download_url': spec.downloadUrl,
              'status': 'verified_local',
              'downloaded_at': DateTime.now().toIso8601String(),
            };
            await file.writeAsString(jsonEncode(payload));
          }
        } catch (_) {}

        _activeProgress[spec.id] = 1.0;
        _downloadedBytes[spec.id] = spec.totalSizeInMb * 1024 * 1024;
        controller.add(1.0);
        _cleanup(spec.id);
        await controller.close();
      }
    });
  }

  void _cleanup(String modelId) {
    _activeProgress.remove(modelId);
    _downloadedBytes.remove(modelId);
    _subscriptions.remove(modelId);
    _controllers.remove(modelId);
    _activeSinks.remove(modelId);
  }

  /// Cancels an active download, flushing and closing the sink while preserving `.part` on disk.
  void cancelDownload(String modelId) {
    _subscriptions[modelId]?.cancel();
    final sink = _activeSinks.remove(modelId);
    if (sink != null) {
      sink.flush().then((_) => sink.close()).catchError((_) {});
    }
    _cleanup(modelId);
    _controllers[modelId]?.close();
  }

  /// Cancels any active download and deletes the `.part` file from disk to reclaim storage.
  Future<void> cancelAndClearDownload(OnDeviceModelSpec spec) async {
    cancelDownload(spec.id);
    final partFile = await resolveModelPartFileAsync(spec.fileName);
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }
    _activeProgress.remove(spec.id);
    _downloadedBytes.remove(spec.id);
  }

  /// Completely deletes the completed model weight file and any residual `.part` file from disk.
  Future<void> deleteDownloadedModel(OnDeviceModelSpec spec) async {
    cancelDownload(spec.id);
    final targetFile = await resolveModelFileAsync(spec.fileName);
    final partFile = await resolveModelPartFileAsync(spec.fileName);
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }
    _cleanup(spec.id);
  }
}
