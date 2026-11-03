import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/utils/network_guard.dart';
import 'transfer_exception.dart';

/// Structured result of an outbound `http_request`.
class HttpTransferResult {
  /// HTTP status code.
  final int status;

  /// Response headers.
  final Map<String, String> headers;

  /// Response body decoded as UTF-8.
  final String body;

  /// True when the body exceeded the 1 MB cap and was cut.
  final bool truncated;

  const HttpTransferResult({
    required this.status,
    required this.headers,
    required this.body,
    required this.truncated,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'headers': headers,
        'body': body,
        'truncated': truncated,
      };
}

/// Executes a single outbound HTTP request for FEAT-009.
///
/// Only allowlisted hosts are contacted. Redirects are not followed, so a
/// 3xx response can never bypass the allowlist or the SSRF guard.
class HttpTransferClient {
  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Maximum response body bytes retained (1 MB).
  final int maxResponseBytes;

  /// Creates a client with the FEAT-009 defaults.
  HttpTransferClient({
    this.client,
    this.maxResponseBytes = 1000000,
  });

  /// Sends [method] to [url] on behalf of the agent.
  Future<HttpTransferResult> send({
    required String method,
    required Uri url,
    required Iterable<String> allowedHosts,
    int timeoutSeconds = 30,
    Map<String, String>? headers,
    String? body,
    Map<String, dynamic>? jsonBody,
    File? uploadFile,
  }) async {
    _assertAllowed(url, allowedHosts);

    final request = await _buildRequest(
      method: method,
      url: url,
      headers: headers,
      body: body,
      jsonBody: jsonBody,
      uploadFile: uploadFile,
    );

    try {
      final response = await (client ?? http.Client())
          .send(request)
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw TransferException(
          'HTTP ${response.statusCode} redirect was not followed. Request the final URL directly.',
        );
      }

      final bytes = await _readCapped(response.stream);
      return HttpTransferResult(
        status: response.statusCode,
        headers: response.headers,
        body: utf8.decode(bytes.data, allowMalformed: true),
        truncated: bytes.truncated,
      );
    } on TimeoutException {
      throw TransferException(
        'Request timed out after ${timeoutSeconds}s.',
      );
    } on http.ClientException catch (e) {
      throw TransferException('Failed to reach ${url.host}: ${e.message}');
    }
  }

  Future<http.BaseRequest> _buildRequest({
    required String method,
    required Uri url,
    required Map<String, String>? headers,
    required String? body,
    required Map<String, dynamic>? jsonBody,
    required File? uploadFile,
  }) async {
    if (uploadFile != null) {
      final request = http.MultipartRequest(method, url);
      if (headers != null) request.headers.addAll(headers);
      if (body != null && body.isNotEmpty) request.fields['body'] = body;
      if (jsonBody != null) request.fields['json'] = json.encode(jsonBody);
      request.files.add(
        await http.MultipartFile.fromPath('file', uploadFile.path),
      );
      request.followRedirects = false;
      return request;
    }

    final request = http.Request(method, url)..followRedirects = false;
    if (headers != null) request.headers.addAll(headers);

    // `Request.body` defaults the content type to text/plain, so remember
    // whether the caller supplied one before assigning the JSON payload.
    final hasExplicitContentType = request.headers.keys.any(
      (key) => key.toLowerCase() == 'content-type',
    );

    if (jsonBody != null) {
      request.body = json.encode(jsonBody);
      if (!hasExplicitContentType) {
        request.headers['Content-Type'] = 'application/json';
      }
    } else if (body != null) {
      request.body = body;
    }

    return request;
  }

  /// Reads the body while enforcing [maxResponseBytes].
  Future<_CappedBody> _readCapped(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    var truncated = false;

    await for (final chunk in stream) {
      final remaining = maxResponseBytes - total;
      if (chunk.length > remaining) {
        if (remaining > 0) builder.add(chunk.sublist(0, remaining));
        truncated = true;
        break;
      }
      builder.add(chunk);
      total += chunk.length;
    }

    return _CappedBody(data: builder.takeBytes(), truncated: truncated);
  }

  /// Validates the public-target rules and the user allowlist.
  void _assertAllowed(Uri url, Iterable<String> allowedHosts) {
    try {
      assertPublicHttpUri(url);
    } on UnsafeNetworkTargetException catch (e) {
      throw TransferException(e.message);
    }

    if (!isHostAllowed(url.host, url.hasPort ? url.port : null, allowedHosts)) {
      throw TransferException(
        'Host "${url.host}" is not on the allowed hosts list. '
        'Ask the user to allow it in Settings before retrying.',
      );
    }
  }
}

class _CappedBody {
  final List<int> data;
  final bool truncated;

  const _CappedBody({required this.data, required this.truncated});
}
