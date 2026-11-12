import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'model_provider.dart';

/// Retries transient model-provider HTTP failures before surfacing an error.
///
/// Retrying happens at the inference-request boundary only. Tool calls and the
/// surrounding agent turn are never re-executed, so a retry cannot duplicate a
/// side effect.
class ModelHttpRetry {
  /// Maximum number of attempts, including the initial request.
  static const int defaultMaxAttempts = 10;

  static const Duration _baseDelay = Duration(milliseconds: 750);
  static const Duration _maxDelay = Duration(seconds: 15);
  static final Random _random = Random();

  /// Sends a POST request, retrying transient failures.
  ///
  /// A retryable status is returned to the caller on the final attempt so the
  /// provider can produce its normal status-specific error message. Network
  /// failures are retried and then surfaced as a [ModelProviderException].
  static Future<http.Response> post({
    required http.Client client,
    required Uri url,
    required Map<String, String> headers,
    required String body,
    required String provider,
    int maxAttempts = defaultMaxAttempts,
    Future<void> Function(Duration duration)? wait,
    void Function(ModelRetryEvent event)? onRetry,
  }) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    final delay = wait ?? (duration) => Future<void>.delayed(duration);
    Object? lastNetworkError;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await client.post(
          url,
          headers: headers,
          body: body,
        );

        if (!_isRetryableStatus(response.statusCode) || attempt == attempts) {
          return response;
        }

        final delayForRetry = _delayFor(attempt, _retryAfter(response));
        onRetry?.call(ModelRetryEvent(
          phase: ModelRetryPhase.waiting,
          attempt: attempt,
          maxAttempts: attempts,
          delay: delayForRetry,
          reason: 'HTTP ${response.statusCode}',
        ));
        debugPrint(
          'ModelHttpRetry: $provider returned ${response.statusCode}; '
          'retrying in ${delayForRetry.inMilliseconds}ms '
          '(attempt $attempt/$attempts).',
        );
        await delay(delayForRetry);
        onRetry?.call(ModelRetryEvent(
          phase: ModelRetryPhase.attempting,
          attempt: attempt + 1,
          maxAttempts: attempts,
          reason: 'resuming',
        ));
      } on IOException catch (error) {
        lastNetworkError = error;
        if (attempt == attempts) break;
        await _wait(
          attempt,
          provider,
          error,
          attempts,
          delay,
          onRetry,
        );
      } on TimeoutException catch (error) {
        lastNetworkError = error;
        if (attempt == attempts) break;
        await _wait(
          attempt,
          provider,
          error,
          attempts,
          delay,
          onRetry,
        );
      } on http.ClientException catch (error) {
        lastNetworkError = error;
        if (attempt == attempts) break;
        await _wait(
          attempt,
          provider,
          error,
          attempts,
          delay,
          onRetry,
        );
      }
    }

    throw ModelProviderException(
      provider: provider,
      message:
          'Request failed after $attempts attempts: ${lastNetworkError ?? 'unknown network error'}.',
    );
  }

  static bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  static Future<void> _wait(
    int attempt,
    String provider,
    Object error,
    int attempts,
    Future<void> Function(Duration duration) delay,
    void Function(ModelRetryEvent event)? onRetry,
  ) async {
    final duration = _delayFor(attempt, null);
    onRetry?.call(ModelRetryEvent(
      phase: ModelRetryPhase.waiting,
      attempt: attempt,
      maxAttempts: attempts,
      delay: duration,
      reason: error.runtimeType.toString(),
    ));
    debugPrint(
      'ModelHttpRetry: $provider request failed with '
      '${error.runtimeType}; retrying in ${duration.inMilliseconds}ms '
      '(attempt $attempt/$attempts).',
    );
    await delay(duration);
    onRetry?.call(ModelRetryEvent(
      phase: ModelRetryPhase.attempting,
      attempt: attempt + 1,
      maxAttempts: attempts,
      reason: 'resuming',
    ));
  }

  static Duration _delayFor(int attempt, Duration? retryAfter) {
    if (retryAfter != null) {
      return retryAfter > _maxDelay ? _maxDelay : retryAfter;
    }

    final exponentialMs = _baseDelay.inMilliseconds * pow(2, attempt - 1);
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    final millis = min(
      (exponentialMs * jitter).round(),
      _maxDelay.inMilliseconds,
    );
    return Duration(milliseconds: millis);
  }

  static Duration? _retryAfter(http.Response response) {
    final raw = response.headers['retry-after'] ??
        response.headers['Retry-After'];
    if (raw == null) return null;

    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }

    try {
      final date = HttpDate.parse(raw);
      final difference = date.difference(DateTime.now().toUtc());
      if (difference.isNegative) return Duration.zero;
      return difference;
    } catch (_) {
      return null;
    }
  }
}
