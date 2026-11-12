import 'dart:async';
import 'package:harness/providers/local_device_model_provider.dart';

/// Test-only stub implementation of [OnDeviceInferenceEngine] for unit testing,
/// CI test runners, and benchmark verification where real model weights and native
/// neural execution runtimes are not loaded.
///
/// MUST NOT be used in production runtime.
class StubOnDeviceInferenceEngine implements OnDeviceInferenceEngine {
  final int simulatedMemoryMb;

  const StubOnDeviceInferenceEngine({
    this.simulatedMemoryMb = 1100,
  });

  @override
  Future<String> generate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    int contextWindowTokens = 4096,
    String? modelPath,
  }) async {
    return _produceResponse(prompt, modelPath);
  }

  @override
  Stream<String> streamGenerate(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
    int contextWindowTokens = 4096,
    String? modelPath,
  }) async* {
    final response = _produceResponse(prompt, modelPath);
    final parts = response.split(' ');
    for (int i = 0; i < parts.length; i++) {
      yield i == parts.length - 1 ? parts[i] : '${parts[i]} ';
    }
  }

  String _produceResponse(String prompt, String? modelPath) {
    if (modelPath == null ||
        modelPath.isEmpty ||
        modelPath.toLowerCase().contains('none') ||
        modelPath.toLowerCase().contains('download required')) {
      return '<system_call>{"command": "send_ui_message", "parameters": {"message": "⚠️ **No On-Device Model Downloaded**\\n\\nPlease navigate to **Settings > Model & Provider Settings**, select **On-Device SLM**, and tap **Download** on a local model (such as Qwen 2.5 or Gemma 2) to enable offline local inference."}}</system_call>';
    }

    final lower = prompt.toLowerCase();
    final modelName = modelPath.split('/').last.split('\\').last;

    if (lower.contains('list') &&
        (lower.contains('file') || lower.contains('directory') || lower.contains('storage'))) {
      return '<system_call>{"command": "list_directory", "parameters": {"path": "workspace"}}</system_call>';
    }
    if (lower.contains('search') || lower.contains('grep')) {
      return '<system_call>{"command": "grep", "parameters": {"pattern": "TODO", "path": "workspace"}}</system_call>';
    }

    if (modelName.toLowerCase().contains('deepseek') || modelName.toLowerCase().contains('r1')) {
      return '<think>\nEvaluating query offline on-device.\n</think>\n<system_call>{"command": "send_ui_message", "parameters": {"message": "Hello! I am DeepSeek-R1 running locally on your device."}}</system_call>';
    }

    return '<system_call>{"command": "send_ui_message", "parameters": {"message": "Test response from $modelName."}}</system_call>';
  }

  @override
  Future<int> getMemoryUsageMb() async => simulatedMemoryMb;

  @override
  Future<void> unload() async {}
}

