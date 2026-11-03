/// Failure raised by the network transfer module.
class TransferException implements Exception {
  /// Human- and model-readable explanation.
  final String message;

  const TransferException(this.message);

  @override
  String toString() => message;
}
