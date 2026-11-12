import 'on_device_model_spec.dart';
import 'provider_config.dart';

/// Default maximum response length for remote cloud/server providers.
///
/// Remote models generally support much larger completions than on-device
/// SLMs. 16,384 tokens is large enough for the multi-file/tool-call workloads
/// that previously truncated at 4,096 tokens, while remaining within the
/// output limits of most current providers.
const int kDefaultRemoteMaxOutputTokens = 16384;

/// Default maximum response length for on-device SLMs.
const int kDefaultLocalMaxOutputTokens = 1024;

/// Selectable output-token budgets for remote providers.
///
/// The selected value is sent as `max_tokens` / `maxOutputTokens` to the
/// provider. Providers and individual models may enforce a lower cap; the
/// settings UI surfaces that caveat rather than silently hiding the option.
const List<int> kRemoteMaxOutputTokenOptions = [
  4096,
  8192,
  16384,
  32768,
  65536,
];

/// Selectable output-token budgets for on-device SLMs.
///
/// Local bundles are small and must leave room for the prompt inside their
/// context window, so the list is intentionally separate from remote options.
const List<int> kLocalMaxOutputTokenOptions = [
  256,
  512,
  1024,
  2048,
];

/// Resolves the [OnDeviceModelSpec] associated with [config], if any.
///
/// The preferred lookup key is `extraConfig['selectedModelSpecId']`, because
/// the user may rename or otherwise alter the stored model filename. A filename
/// match is used as a fallback for configs created before that key existed.
OnDeviceModelSpec? findOnDeviceModelSpec(ProviderConfig config) {
  final selectedId = config.extraConfig['selectedModelSpecId'];
  if (selectedId is String && selectedId.trim().isNotEmpty) {
    for (final spec in kSupportedOnDeviceModels) {
      if (spec.id == selectedId) return spec;
    }
  }

  for (final spec in kSupportedOnDeviceModels) {
    if (spec.fileName == config.modelName) return spec;
  }

  return null;
}

/// Maximum output tokens allowed for the on-device model in [config].
///
/// Falls back to [kDefaultLocalMaxOutputTokens] when the selected model cannot
/// be identified, so an unrecognized local configuration still receives a safe
/// mobile-sized cap.
int localMaxOutputTokensFor(ProviderConfig config) {
  return findOnDeviceModelSpec(config)?.maxOutputTokens ??
      kDefaultLocalMaxOutputTokens;
}

/// Context window used to load the on-device model in [config].
int localContextWindowTokensFor(ProviderConfig config) {
  final spec = findOnDeviceModelSpec(config);
  final configured = config.extraConfig['contextWindowTokens'];
  if (configured is int && configured > 0) {
    // Never let a stale or hand-edited value exceed what the bundle supports.
    return spec == null ? configured : configured.clamp(1024, spec.contextWindowTokens);
  }

  return spec?.contextWindowTokens ?? 4096;
}

/// Normalizes a configured output budget for the provider type.
///
/// Remote values are returned unchanged. Local values are clamped to the
/// selected model's recommended maximum so a remote-sized value (for example
/// 16,384) can never be passed to an on-device SLM.
int resolveMaxOutputTokens(ProviderConfig config) {
  if (config.providerType != 'local_device') {
    return config.maxOutputTokens;
  }

  return config.maxOutputTokens.clamp(1, localMaxOutputTokensFor(config));
}

/// Returns the token options that should be shown for [config].
///
/// Local options are filtered by the selected model's cap, and the cap itself
/// is included even when it is not one of the standard list values. Remote
/// options include the currently configured value so a hand-edited or migrated
/// value never produces an invalid dropdown selection.
List<int> maxOutputTokenOptionsFor(ProviderConfig config) {
  if (config.providerType != 'local_device') {
    final values = <int>{
      ...kRemoteMaxOutputTokenOptions,
      config.maxOutputTokens,
    }.toList()
      ..sort();
    return values;
  }

  final cap = localMaxOutputTokensFor(config);
  final values = kLocalMaxOutputTokenOptions.where((value) => value <= cap).toList();
  if (values.isEmpty) values.add(cap);
  if (!values.contains(cap)) values.add(cap);
  values.sort();
  return values;
}
