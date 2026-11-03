import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../../core/utils/file_system_manager.dart';
import '../../core/utils/network_guard.dart';
import '../base/harness_module.dart';
import 'http_transfer_client.dart';
import 'media_downloader.dart';
import 'transfer_exception.dart';

/// Exposes media downloads and outbound HTTP requests as harness commands.
///
/// Implements FEAT-009:
/// - `download_media` streams a public media file into any registered storage
///   volume (`primary` by default) without a dedicated media directory.
/// - `http_request` performs a single request to an allowlisted host, with
///   optional text/JSON body or a multipart upload from registered storage.
class TransferModule extends HarnessModule {
  /// Resolves the hosts approved for `http_request`.
  final Future<List<String>> Function() allowedHostsProvider;

  /// Resolves the active filesystem, or null when storage is unavailable.
  final HarnessFileSystem? Function() fileSystemProvider;

  /// Optional HTTP client shared by the downloader and request client.
  final http.Client? client;

  /// Maximum retained `http_request` response bytes (1 MB by default).
  final int maxResponseBytes;

  /// Creates the module with configuration providers.
  TransferModule({
    required this.allowedHostsProvider,
    required this.fileSystemProvider,
    this.client,
    this.maxResponseBytes = 1000000,
  });

  static const Set<String> supportedMethods = {
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };

  @override
  String get moduleName => 'transfer';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'download_media',
          description:
              'Downloads an image, audio, video, or PDF file from a public URL into a registered storage volume. Defaults to the root of primary.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'Absolute public http(s) URL of the media file.',
              },
              'storage': {
                'type': 'string',
                'description':
                    'Registered storage tag (default "primary", or an external mount).',
              },
              'path': {
                'type': 'string',
                'description':
                    'Optional relative destination path inside the selected storage. Directories are created.',
              },
              'filename': {
                'type': 'string',
                'description':
                    'Optional filename when path is omitted or names a directory.',
              },
            },
            'required': ['url'],
          },
        ),
        CommandDefinition(
          command: 'http_request',
          description:
              'Sends one HTTP request to an allowlisted host and returns the status, headers, and response body. Supports JSON or text bodies and multipart uploads from storage.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'method': {
                'type': 'string',
                'enum': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
              },
              'url': {
                'type': 'string',
                'description': 'Absolute public http(s) URL.',
              },
              'headers': {
                'type': 'object',
                'additionalProperties': {'type': 'string'},
              },
              'body': {
                'type': 'string',
                'description': 'Raw request body. Mutually exclusive with json.',
              },
              'json': {
                'type': 'object',
                'description':
                    'JSON body serialized with a JSON content type. Mutually exclusive with body.',
              },
              'filePath': {
                'type': 'string',
                'description':
                    'Virtual path in a registered storage sent as a multipart file upload.',
              },
              'timeoutSeconds': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 120,
                'description': 'Request timeout in seconds. Defaults to 30.',
              },
            },
            'required': ['method', 'url'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    switch (command) {
      case 'download_media':
        return _handleDownload(parameters);
      case 'http_request':
        return _handleHttpRequest(parameters);
      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unrecognized transfer command: "$command".',
        );
    }
  }

  /// Validates and executes `download_media`.
  Future<SystemResponse> _handleDownload(
    Map<String, dynamic> parameters,
  ) async {
    final url = _stringParam(parameters, 'url');
    if (url == null) {
      return _validationError(
        'download_media',
        'Missing or invalid "url". Provide an absolute http(s) media URL.',
      );
    }

    final storage = _stringParam(parameters, 'storage') ?? 'primary';
    final path = _stringParam(parameters, 'path');
    final filename = _stringParam(parameters, 'filename');

    try {
      final downloader = MediaDownloader(
        fileSystemProvider: fileSystemProvider,
        client: client,
      );
      final result = await downloader.download(
        url: url,
        storage: storage,
        path: path,
        filename: filename,
      );
      return SystemResponse.success(
        command: 'download_media',
        data: result.toJson(),
      );
    } on TimeoutException {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: 'Download timed out.',
      );
    } on UnsafeNetworkTargetException catch (e) {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: e.message,
      );
    } on TransferException catch (e) {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: e.message,
      );
    } on SecurityException catch (e) {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: e.message,
      );
    } on UnknownVolumeException catch (e) {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: e.message,
      );
    } catch (e) {
      return SystemResponse.error(
        command: 'download_media',
        errorMessage: 'Download failed: $e',
      );
    }
  }

  /// Validates and executes `http_request`.
  Future<SystemResponse> _handleHttpRequest(
    Map<String, dynamic> parameters,
  ) async {
    final method = _stringParam(parameters, 'method')?.toUpperCase();
    if (method == null || !supportedMethods.contains(method)) {
      return _validationError(
        'http_request',
        'Invalid "method": expected one of ${supportedMethods.join(', ')}.',
      );
    }

    final rawUrl = _stringParam(parameters, 'url');
    final uri = Uri.tryParse(rawUrl ?? '');
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return _validationError(
        'http_request',
        'Invalid "url": expected an absolute http or https URL.',
      );
    }

    final headers = _parseHeaders(parameters['headers']);
    if (headers == null) {
      return _validationError(
        'http_request',
        'Invalid "headers": expected a map of string values.',
      );
    }

    final body = parameters['body'];
    final jsonBody = parameters['json'];
    if (body != null && body is! String) {
      return _validationError(
        'http_request',
        'Invalid "body": expected a string.',
      );
    }
    if (jsonBody != null && jsonBody is! Map) {
      return _validationError(
        'http_request',
        'Invalid "json": expected an object.',
      );
    }
    if (body != null && jsonBody != null) {
      return _validationError(
        'http_request',
        '"body" and "json" are mutually exclusive.',
      );
    }

    final rawTimeout = parameters['timeoutSeconds'] ?? 30;
    if (rawTimeout is! int || rawTimeout < 1 || rawTimeout > 120) {
      return _validationError(
        'http_request',
        'Invalid "timeoutSeconds": expected an integer between 1 and 120.',
      );
    }

    File? uploadFile;
    final filePath = _stringParam(parameters, 'filePath');
    if (filePath != null) {
      final fileSystem = fileSystemProvider();
      if (fileSystem == null) {
        return SystemResponse.error(
          command: 'http_request',
          errorMessage: 'Storage is not initialized; cannot upload a file.',
        );
      }
      try {
        uploadFile = fileSystem.resolveVirtualFile(filePath);
      } on SecurityException catch (e) {
        return SystemResponse.error(
          command: 'http_request',
          errorMessage: e.message,
        );
      } on UnknownVolumeException catch (e) {
        return SystemResponse.error(
          command: 'http_request',
          errorMessage: e.message,
        );
      }
      if (!await uploadFile.exists()) {
        return SystemResponse.error(
          command: 'http_request',
          errorMessage: 'Upload file "$filePath" does not exist in storage.',
        );
      }
    }

    try {
      final allowedHosts = await allowedHostsProvider();
      if (allowedHosts.isEmpty) {
        return SystemResponse.error(
          command: 'http_request',
          errorMessage:
              'No allowed hosts are configured. Add the target host in Settings before sending requests.',
        );
      }

      final transferClient = HttpTransferClient(
        client: client,
        maxResponseBytes: maxResponseBytes,
      );
      final result = await transferClient.send(
        method: method,
        url: uri,
        allowedHosts: allowedHosts,
        timeoutSeconds: rawTimeout,
        headers: headers,
        body: body as String?,
        jsonBody: jsonBody == null
            ? null
            : Map<String, dynamic>.from(jsonBody as Map),
        uploadFile: uploadFile,
      );

      return SystemResponse.success(
        command: 'http_request',
        data: result.toJson(),
      );
    } on TimeoutException {
      return SystemResponse.error(
        command: 'http_request',
        errorMessage: 'Request timed out after ${rawTimeout}s.',
      );
    } on UnsafeNetworkTargetException catch (e) {
      return SystemResponse.error(
        command: 'http_request',
        errorMessage: e.message,
      );
    } on TransferException catch (e) {
      return SystemResponse.error(
        command: 'http_request',
        errorMessage: e.message,
      );
    } catch (e) {
      return SystemResponse.error(
        command: 'http_request',
        errorMessage: 'Request failed: $e',
      );
    }
  }

  /// Returns a trimmed non-empty string parameter, or null.
  String? _stringParam(Map<String, dynamic> parameters, String key) {
    final value = parameters[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Parses request headers, or null when the shape is invalid.
  Map<String, String>? _parseHeaders(dynamic raw) {
    if (raw == null) return const {};
    if (raw is! Map) return null;

    final parsed = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.value is! String) return null;
      parsed[entry.key.toString()] = entry.value as String;
    }
    return parsed;
  }

  /// Builds a structured validation error response.
  SystemResponse _validationError(String command, String message) {
    return SystemResponse.error(
      command: command,
      errorMessage: 'Validation error for $command: $message',
    );
  }
}
