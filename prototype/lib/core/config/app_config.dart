/// Application-wide configuration and environment variables.
class AppConfig {
  /// Hugging Face API token for downloading gated models and preventing API rate limits.
  ///
  /// Can be provided at compile-time / run-time using:
  /// `flutter run --dart-define-from-file=.env`
  /// or:
  /// `flutter run --dart-define=HF_TOKEN=hf_...`
  static const String _hfTokenEnv = String.fromEnvironment('HF_TOKEN');

  /// Resolved Hugging Face token, or null if empty.
  static String? get huggingFaceToken {
    final token = _hfTokenEnv.trim();
    return token.isNotEmpty ? token : null;
  }
}
