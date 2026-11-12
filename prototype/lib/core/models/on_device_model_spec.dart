/// Specification descriptor for an on-device model deployable via Google LiteRT-LM (flutter_edge_ai).
class OnDeviceModelSpec {
  /// Unique identifier, e.g. 'qwen_2_5_1_5b' or 'gemma_4_e2b'.
  final String id;

  /// User-facing short name, e.g. 'Qwen 2.5' or 'Gemma 4'.
  final String name;

  /// Parameter size, e.g. '0.6B', '1.5B', or 'E2B'.
  final String parameterSize;

  /// Quantization format, e.g. 'INT4.litertlm' or 'Q8.litertlm'.
  final String format;

  /// Estimated resident memory consumption in megabytes.
  final int memoryUsageMb;

  /// Estimated download bundle size.
  final String downloadSize;

  /// Concise description of the model architecture and strengths.
  final String description;

  /// Local filename stored inside `data/models/`.
  final String fileName;

  /// Maximum prompt + response context prepared for the LiteRT-LM bundle.
  ///
  /// These values are deliberately conservative for mobile execution. The
  /// engine uses this as the model-loading context budget, while
  /// [maxOutputTokens] caps the response length independently.
  final int contextWindowTokens;

  /// Conservative maximum response length recommended for this on-device model.
  ///
  /// Local models have much smaller output budgets than remote providers. The
  /// settings UI and [LocalDeviceModelProvider] clamp user configuration to this
  /// value so a remote-sized token cap can never be applied to an on-device SLM.
  final int maxOutputTokens;

  /// Remote URL for downloading model weights from HuggingFace / CDN.
  final String? downloadUrl;

  const OnDeviceModelSpec({
    required this.id,
    required this.name,
    required this.parameterSize,
    required this.format,
    required this.memoryUsageMb,
    required this.downloadSize,
    required this.description,
    required this.fileName,
    this.contextWindowTokens = 4096,
    this.maxOutputTokens = 1024,
    this.downloadUrl,
  });

  /// Estimated download size in numeric megabytes for transfer calculation.
  int get totalSizeInMb {
    if (downloadSize.contains('GB')) {
      final gb =
          double.tryParse(downloadSize.replaceAll('GB', '').trim()) ?? 1.0;
      return (gb * 1024).round();
    }
    return int.tryParse(downloadSize.replaceAll('MB', '').trim()) ?? 1000;
  }

  /// Tagged memory display label, e.g. '~1.1 GB RAM'.
  String get memoryTag {
    return "~${(memoryUsageMb / 1000).toStringAsFixed(1)} GB RAM";
  }
}

/// Supported on-device small language models deployable via Google LiteRT-LM (flutter_edge_ai).
const List<OnDeviceModelSpec> kSupportedOnDeviceModels = [
  OnDeviceModelSpec(
    id: 'gemma_4_e2b',
    name: 'Gemma 4',
    parameterSize: 'E2B',
    format: 'Mix-INT4.litertlm',
    memoryUsageMb: 1600,
    downloadSize: '2.4 GB',
    description:
        'A versatile assistant from Google that answers questions and handles everyday tasks quickly and reliably.',
    fileName: 'gemma-4-E2B-it.litertlm',
    contextWindowTokens: 4096,
    maxOutputTokens: 1024,
    downloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  ),
  OnDeviceModelSpec(
    id: 'qwen_2_5_1_5b',
    name: 'Qwen 2.5',
    parameterSize: '1.5B',
    format: 'Q8.litertlm',
    memoryUsageMb: 1400,
    downloadSize: '1.5 GB',
    description:
        'A fast assistant fluent in many languages, great for chatting and following detailed instructions.',
    fileName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    // The `ekv4096` bundle name encodes a 4,096-token KV cache.
    contextWindowTokens: 4096,
    maxOutputTokens: 1024,
    downloadUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
  ),
  OnDeviceModelSpec(
    id: 'deepseek_r1_1_5b',
    name: 'DeepSeek-R1',
    parameterSize: '1.5B',
    format: 'Q8.litertlm',
    memoryUsageMb: 1500,
    downloadSize: '1.8 GB',
    description:
        'Thinks through questions step by step before answering. Ideal for math, logic, and complex problems.',
    fileName:
        'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
    // The `ekv4096` bundle name encodes a 4,096-token KV cache.
    contextWindowTokens: 4096,
    maxOutputTokens: 1024,
    downloadUrl:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
  ),
  OnDeviceModelSpec(
    id: 'qwen_3_0_6b',
    name: 'Qwen 3',
    parameterSize: '0.6B',
    format: 'INT4.litertlm',
    memoryUsageMb: 650,
    downloadSize: '614 MB',
    description:
        'Compact and super fast. Uses minimal storage and battery, perfect for quick answers on any device.',
    fileName: 'Qwen3-0.6B.litertlm',
    contextWindowTokens: 4096,
    maxOutputTokens: 1024,
    downloadUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
  ),
];
