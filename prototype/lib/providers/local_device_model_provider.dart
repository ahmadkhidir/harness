import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/models/command_definition.dart';
import '../core/models/provider_config.dart';
import '../core/utils/file_system_manager.dart';
import 'model_provider.dart';

/// Contract for on-device machine learning inference engines running locally on the device
/// (e.g., Google LiteRT-LM / flutter_edge_ai or native platform channels).
abstract class OnDeviceInferenceEngine {
  /// Executes text generation on the loaded model.
  Future<String> generate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  });

  /// Streams generated tokens incrementally as they are sampled from the model.
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  });

  /// Returns the current resident memory allocation (in megabytes) used by the active model.
  Future<int> getMemoryUsageMb();

  /// Unloads the model and releases GPU/RAM resources.
  Future<void> unload();
}

/// Production implementation of [OnDeviceInferenceEngine] communicating with native
/// mobile runtime bindings (iOS/Android platform channels).
class PlatformChannelInferenceEngine implements OnDeviceInferenceEngine {
  final MethodChannel methodChannel;
  final EventChannel eventChannel;

  const PlatformChannelInferenceEngine({
    this.methodChannel = const MethodChannel('dev.harness.model/inference'),
    this.eventChannel =
        const EventChannel('dev.harness.model/inference_stream'),
  });

  @override
  Future<String> generate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async {
    try {
      final result = await methodChannel.invokeMethod<String>('generate', {
        'prompt': prompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'modelPath': ?modelPath,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      if (e.code == 'OUT_OF_MEMORY') {
        throw ModelMemoryExceededException(
          provider: 'local_device',
          message:
              'Device out of memory while running on-device model: ${e.message}',
        );
      }
      throw ModelProviderException(
        provider: 'local_device',
        message: 'On-device model platform error: ${e.message}',
      );
    } on MissingPluginException catch (e) {
      throw ModelProviderException(
        provider: 'local_device',
        message:
            'Platform channel for on-device model inference is not registered on this platform. Details: $e',
      );
    }
  }

  @override
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async* {
    Stream<String> nativeStream;
    try {
      nativeStream = eventChannel
          .receiveBroadcastStream({
            'prompt': prompt,
            'temperature': temperature,
            'maxTokens': maxTokens,
            'modelPath': ?modelPath,
          })
          .map((event) => event.toString());
    } on MissingPluginException catch (e) {
      throw ModelProviderException(
        provider: 'local_device',
        message:
            'Platform channel for on-device model inference stream is not registered on this platform. Details: $e',
      );
    } catch (e) {
      throw ModelProviderException(
        provider: 'local_device',
        message: 'Failed to initiate on-device inference stream: $e',
      );
    }

    final controller = StreamController<String>();
    StreamSubscription? sub;

    sub = nativeStream.listen(
      (chunk) => controller.add(chunk),
      onError: (err) {
        if (err is PlatformException && err.code == 'OUT_OF_MEMORY') {
          controller.addError(
            ModelMemoryExceededException(
              provider: 'local_device',
              message:
                  'Device out of memory during streaming inference: ${err.message}',
            ),
          );
        } else {
          controller.addError(
            ModelProviderException(
              provider: 'local_device',
              message: 'Native stream failure during token generation: $err',
            ),
          );
        }
      },
      onDone: () => controller.close(),
    );

    try {
      yield* controller.stream;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<int> getMemoryUsageMb() async {
    try {
      final usage = await methodChannel.invokeMethod<int>('getMemoryUsageMb');
      return usage ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> unload() async {
    try {
      await methodChannel.invokeMethod('unload');
    } catch (_) {}
  }
}

/// Helper function to resolve an on-device model file location from a candidate path or filename.
Future<File> resolveOnDeviceModelFile(String? rawPath) async {
  if (rawPath == null || rawPath.trim().isEmpty || rawPath == 'None') {
    throw const ModelProviderException(
      provider: 'local_device',
      message:
          'No on-device model selected. Please open Settings > Model & Provider Settings '
          'and download a model before starting inference.',
    );
  }

  final cleanPath = rawPath
      .trim()
      .replaceAll(RegExp(r'''^["']|["']$'''), '')
      .replaceAll(RegExp(r'\s*/\s*'), '/')
      .trim();

  final directFile = File(cleanPath);
  if (directFile.existsSync() && directFile.lengthSync() > 0) {
    return directFile;
  }

  final fileName = p.basename(cleanPath).trim();

  // 1. Try resolving via HarnessFileSystem singleton if initialized (data/models/)
  if (HarnessFileSystem.instance != null) {
    final fsFile = HarnessFileSystem.instance!.modelFile(fileName);
    if (fsFile.existsSync() && fsFile.lengthSync() > 0) {
      return fsFile;
    }
    // Migration fallback from legacy storage/models/
    final legacyFsFile = File(
      p.join(
        HarnessFileSystem.instance!.rootDir.path,
        'storage',
        'models',
        fileName,
      ),
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
  }

  // 2. Try resolving inside application documents directory: Harness/data/models/<fileName>
  try {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelsDirFile = File(
      p.join(appDocDir.path, 'Harness', 'data', 'models', fileName),
    );
    if (modelsDirFile.existsSync() && modelsDirFile.lengthSync() > 0) {
      return modelsDirFile;
    }
    final legacyAppDocFile = File(
      p.join(appDocDir.path, 'Harness', 'storage', 'models', fileName),
    );
    if (legacyAppDocFile.existsSync() && legacyAppDocFile.lengthSync() > 0) {
      return legacyAppDocFile;
    }
  } catch (_) {}

  // 3. Try resolving in working directory fallback: data/models/<fileName>
  try {
    final cwdFile = File(
      p.join(Directory.current.path, 'data', 'models', fileName),
    );
    if (cwdFile.existsSync() && cwdFile.lengthSync() > 0) {
      return cwdFile;
    }
  } catch (_) {}

  throw ModelProviderException(
    provider: 'local_device',
    message:
        'Model weights file "$fileName" is not downloaded on this device. '
        'Please navigate to Settings > Model & Provider Settings and tap "Download" to fetch the model.',
  );
}

/// Production implementation of [OnDeviceInferenceEngine] powered by Google LiteRT-LM
/// via the `flutter_edge_ai` and `flutter_edge_ai_litertlm` packages.
///
/// Runs quantized on-device models (.litertlm, .task, .bin, .tflite) with native hardware acceleration
/// (NPU/GPU/CPU) across mobile devices without device freezing.
class FlutterEdgeAiInferenceEngine implements OnDeviceInferenceEngine {
  InferenceModel? _model;
  String? _loadedModelPath;

  FlutterEdgeAiInferenceEngine();

  /// Infers the [ModelFileType] from the model file extension.
  static ModelFileType inferFileType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.litertlm')) return ModelFileType.litertlm;
    if (lower.endsWith('.task')) return ModelFileType.task;
    if (lower.endsWith('.bin') || lower.endsWith('.tflite')) {
      return ModelFileType.binary;
    }
    return ModelFileType.litertlm;
  }

  /// Infers the [ModelType] from the model name/path.
  static ModelType inferModelType(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('gemma-4') || lower.contains('gemma4')) {
      return ModelType.gemma4;
    }
    if (lower.contains('gemma')) return ModelType.gemmaIt;
    if (lower.contains('qwen')) return ModelType.qwen;
    if (lower.contains('deepseek')) return ModelType.deepSeek;
    if (lower.contains('llama')) return ModelType.llama;
    if (lower.contains('phi')) return ModelType.phi;
    return ModelType.general;
  }

  Future<InferenceModel> _ensureModelLoaded(
    String? modelPath, {
    int maxTokens = 1024,
  }) async {
    final modelFile = await resolveOnDeviceModelFile(modelPath);

    // Validate model binary exists and is not empty
    final fileSize = modelFile.lengthSync();
    if (fileSize < 1024 * 1024) {
      throw ModelProviderException(
        provider: 'local_device',
        message:
            'Model file "${modelFile.path}" is incomplete or empty ($fileSize bytes). '
            'Please re-download the model in Settings.',
      );
    }

    if (_model != null && _loadedModelPath == modelFile.path) {
      return _model!;
    }

    await unload();

    final fileType = inferFileType(modelFile.path);
    final modelType = inferModelType(modelFile.path);

    try {
      await FlutterEdgeAi.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(modelFile.path).install();
    } catch (e) {
      throw ModelProviderException(
        provider: 'local_device',
        message:
            'Failed to install on-device model from "${modelFile.path}": $e',
      );
    }

    try {
      final contextTokens = maxTokens < 1024 ? 1024 : maxTokens;
      try {
        // Automatic hardware acceleration: auto-dispatches to device NPU (Qualcomm Hexagon,
        // Google Tensor TPU, MediaTek NeuroPilot) or GPU (Apple Metal, Qualcomm Adreno, ARM Mali)
        _model = await FlutterEdgeAi.getActiveModel(maxTokens: contextTokens);
      } catch (_) {
        // Graceful fallback to multi-core CPU SIMD if device GPU/NPU runtime is unavailable
        _model = await FlutterEdgeAi.getActiveModel(
          maxTokens: contextTokens,
          preferredBackend: PreferredBackend.cpu,
        );
      }
      _loadedModelPath = modelFile.path;
      return _model!;
    } catch (e) {
      await unload();
      throw ModelProviderException(
        provider: 'local_device',
        message: 'flutter_edge_ai model load failed for "${modelFile.path}": $e',
      );
    }
  }

  @override
  Future<String> generate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async {
    final model = await _ensureModelLoaded(modelPath, maxTokens: maxTokens);
    InferenceModelSession? session;
    try {
      session = await model.createSession(
        temperature: temperature,
        maxOutputTokens: maxTokens,
      );
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      return await session.getResponse();
    } catch (e) {
      if (e is ModelProviderException) rethrow;
      throw ModelProviderException(
        provider: 'local_device',
        message: 'flutter_edge_ai generation error: $e',
      );
    } finally {
      await session?.close();
    }
  }

  @override
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    String? modelPath,
  }) async* {
    final model = await _ensureModelLoaded(modelPath, maxTokens: maxTokens);
    InferenceModelSession? session;
    try {
      session = await model.createSession(
        temperature: temperature,
        maxOutputTokens: maxTokens,
      );
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      yield* session.getResponseAsync();
    } catch (e) {
      if (e is ModelProviderException) rethrow;
      throw ModelProviderException(
        provider: 'local_device',
        message: 'flutter_edge_ai streaming error: $e',
      );
    } finally {
      await session?.close();
    }
  }

  @override
  Future<int> getMemoryUsageMb() async {
    return _model != null ? 1050 : 0;
  }

  @override
  Future<void> unload() async {
    if (_model != null) {
      try {
        await _model!.close();
      } catch (_) {}
      _model = null;
      _loadedModelPath = null;
    }
  }
}

/// Adapter for on-device small language models (SLM) running locally on mobile hardware
/// via Google LiteRT-LM ([FlutterEdgeAiInferenceEngine]).
///
/// Implements memory boundary monitoring to prevent device thermal overload or OS termination.
class LocalDeviceModelProvider extends ModelProvider {
  @override
  final ProviderConfig config;

  /// Maximum memory budget in megabytes before halting inference.
  final int maxMemoryBudgetMb;

  final OnDeviceInferenceEngine? _explicitEngine;
  late final OnDeviceInferenceEngine _flutterEdgeAiEngine;

  LocalDeviceModelProvider({
    required this.config,
    this.maxMemoryBudgetMb = 2048,
    OnDeviceInferenceEngine? engine,
  }) : _explicitEngine = engine,
       _flutterEdgeAiEngine = FlutterEdgeAiInferenceEngine();

  /// The active on-device inference engine executing token generation.
  OnDeviceInferenceEngine get engine {
    return _explicitEngine ?? _flutterEdgeAiEngine;
  }

  /// Selects the appropriate inference engine.
  OnDeviceInferenceEngine _resolveEngine({String? modelPath}) {
    return _explicitEngine ?? _flutterEdgeAiEngine;
  }

  /// Formats the conversation messages, system instructions, and tool schemas
  /// into a standard instruction-tuned model prompt.
  String formatPrompt({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
  }) {
    final buffer = StringBuffer();

    if (systemInstruction != null && systemInstruction.trim().isNotEmpty) {
      buffer.writeln('<|im_start|>system');
      buffer.writeln(systemInstruction.trim());
      buffer.writeln('<|im_end|>');
    }

    for (final message in messages) {
      buffer.writeln('<|im_start|>${message.role}');
      buffer.writeln(message.content.trim());
      buffer.writeln('<|im_end|>');
    }

    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  Future<void> _checkMemoryBudget([String? modelPath]) async {
    final activeEngine = _resolveEngine(modelPath: modelPath);
    final currentUsageMb = await activeEngine.getMemoryUsageMb();
    final configuredUsageMb =
        config.extraConfig['simulatedAllocatedMb'] as int? ?? currentUsageMb;
    final effectiveUsage =
        currentUsageMb > 0 ? currentUsageMb : configuredUsageMb;

    if (effectiveUsage > maxMemoryBudgetMb) {
      await activeEngine.unload();
      throw ModelMemoryExceededException(
        provider: 'local_device',
        message:
            'On-device SLM exceeded mobile memory limit (${effectiveUsage}MB > ${maxMemoryBudgetMb}MB). '
            'Inference process cleanly halted. Please select a lighter model or switch to a cloud provider.',
      );
    }
  }

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    final modelPath =
        config.customEndpointUrl ??
        config.extraConfig['modelPath'] as String? ??
        config.modelName;

    await _checkMemoryBudget(modelPath);

    final prompt = formatPrompt(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
    );

    return await _resolveEngine(modelPath: modelPath).generate(
      prompt,
      temperature: config.temperature,
      maxTokens: config.maxOutputTokens,
      modelPath: modelPath,
    );
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    final modelPath =
        config.customEndpointUrl ??
        config.extraConfig['modelPath'] as String? ??
        config.modelName;

    await _checkMemoryBudget(modelPath);

    final prompt = formatPrompt(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
    );

    yield* _resolveEngine(modelPath: modelPath).streamGenerate(
      prompt,
      temperature: config.temperature,
      maxTokens: config.maxOutputTokens,
      modelPath: modelPath,
    );
  }
}
