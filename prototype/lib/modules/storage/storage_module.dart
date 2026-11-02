import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../../core/utils/file_system_manager.dart';
import '../base/harness_module.dart';

/// Sandboxed Storage & Filesystem Module.
///
/// Implements FEAT-004:
/// - Provides safe, sandboxed filesystem access via [VirtualMountTable] with zero host path leakage.
/// - Exposes 5 core storage commands:
///   1. `read_file`: Reads text content with line-range offsets and 1MB truncation guard.
///   2. `write_file`: Creates or updates a file (synthesizing parent directories automatically).
///   3. `grep`: Regex or keyword pattern search across files returning matching lines with line numbers.
///   4. `glob`: File pattern matching (`**/*.md`, `*.json`) returning matching virtual file paths.
///   5. `list_directory`: Lists directory entries within a virtual folder.
class StorageModule extends HarnessModule {
  final HarnessFileSystem? fileSystem;

  StorageModule({this.fileSystem});

  HarnessFileSystem get fs => fileSystem ?? HarnessFileSystem.instance!;

  @override
  String get moduleName => 'storage';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'read_file',
          description:
              'Reads text content from a virtual storage file with optional line-range offsets (1-based inclusive). Files larger than 1 MB without line ranges are truncated to 200 lines.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description':
                    'Virtual path of the file to read (e.g. "primary/notes.txt" or "downloads/data.csv").',
              },
              'start_line': {
                'type': 'integer',
                'description': '1-based starting line number to read (inclusive).',
              },
              'end_line': {
                'type': 'integer',
                'description': '1-based ending line number to read (inclusive).',
              },
            },
            'required': ['path'],
          },
        ),
        CommandDefinition(
          command: 'write_file',
          description:
              'Creates or updates a file in virtual storage, automatically synthesizing parent directories.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description':
                    'Virtual path of the file to write (e.g. "primary/output/summary.md").',
              },
              'content': {
                'type': 'string',
                'description': 'Full text content to write into the file.',
              },
              'append': {
                'type': 'boolean',
                'description':
                    'If true, appends content to the end of the file instead of overwriting.',
              },
            },
            'required': ['path', 'content'],
          },
        ),
        CommandDefinition(
          command: 'grep',
          description:
              'Searches for regex or keyword pattern across files in virtual storage returning matching lines with line numbers.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'pattern': {
                'type': 'string',
                'description': 'Regex or text pattern to search for in files.',
              },
              'path': {
                'type': 'string',
                'description':
                    'Virtual path of the directory or file to search within (e.g. "primary/src/" or "primary"). Defaults to "primary".',
              },
              'recursive': {
                'type': 'boolean',
                'description':
                    'Whether to search subdirectories recursively. Defaults to true.',
              },
              'case_sensitive': {
                'type': 'boolean',
                'description': 'Whether the search is case-sensitive. Defaults to true.',
              },
            },
            'required': ['pattern'],
          },
        ),
        CommandDefinition(
          command: 'glob',
          description:
              'Matches files in virtual storage against a glob pattern (e.g. "**/*.md", "*.json").',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'pattern': {
                'type': 'string',
                'description':
                    'Glob pattern to match file names (e.g. "**/*.md", "*.json").',
              },
              'path': {
                'type': 'string',
                'description':
                    'Virtual directory path to search within (e.g. "primary"). Defaults to "primary".',
              },
            },
            'required': ['pattern'],
          },
        ),
        CommandDefinition(
          command: 'list_directory',
          description:
              'Lists files and directories inside a virtual storage folder.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description':
                    'Virtual path of the directory to list (e.g. "primary" or "primary/src"). Defaults to "primary".',
              },
            },
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    try {
      switch (command) {
        case 'read_file':
          return _handleReadFile(parameters);
        case 'write_file':
          return _handleWriteFile(parameters);
        case 'grep':
          return _handleGrep(parameters);
        case 'glob':
          return _handleGlob(parameters);
        case 'list_directory':
          return _handleListDirectory(parameters);
        default:
          return SystemResponse.error(
            command: command,
            errorMessage: 'Unrecognized storage command: "$command".',
          );
      }
    } on SecurityException catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: e.message,
      );
    } on UnknownVolumeException catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: e.message,
      );
    } catch (e) {
      return SystemResponse.error(
        command: command,
        errorMessage: 'Storage operation failed: $e',
      );
    }
  }

  SystemResponse _handleReadFile(Map<String, dynamic> parameters) {
    final virtualPath = parameters['path'] as String?;
    if (virtualPath == null || virtualPath.trim().isEmpty) {
      return SystemResponse.error(
        command: 'read_file',
        errorMessage: 'Missing required parameter "path".',
      );
    }

    final file = fs.mounts.resolveVirtualFile(virtualPath);
    if (!file.existsSync()) {
      return SystemResponse.error(
        command: 'read_file',
        errorMessage: 'File not found: "$virtualPath"',
      );
    }

    final startLine = parameters['start_line'] as int?;
    final endLine = parameters['end_line'] as int?;

    // Large file check (> 1 MB = 1,048,576 bytes) without line range
    final fileSize = file.lengthSync();
    if (fileSize > 1024 * 1024 && startLine == null && endLine == null) {
      final lines = <String>[];
      final reader = file.openSync();
      try {
        final buffer = <int>[];
        while (lines.length < 200) {
          final byte = reader.readByteSync();
          if (byte == -1) break;
          if (byte == 10) {
            lines.add(String.fromCharCodes(buffer));
            buffer.clear();
          } else if (byte != 13) {
            buffer.add(byte);
          }
        }
        if (buffer.isNotEmpty && lines.length < 200) {
          lines.add(String.fromCharCodes(buffer));
        }
      } finally {
        reader.closeSync();
      }
      final content = lines.join('\n');
      final warning =
          '\n\n[Truncated: File exceeds 1 MB limit. Showing first 200 lines. Use start_line and end_line parameters to read further.]';
      return SystemResponse.success(
        command: 'read_file',
        data: '$content$warning',
      );
    }

    // Line range slicing
    if (startLine != null || endLine != null) {
      final allLines = file.readAsLinesSync();
      final total = allLines.length;

      // 1-based indexing
      final start = startLine != null ? (startLine - 1).clamp(0, total) : 0;
      final end = endLine != null ? endLine.clamp(0, total) : total;

      if (start >= total || start > end) {
        return SystemResponse.success(
          command: 'read_file',
          data: '',
        );
      }

      final sliced = allLines.sublist(start, end).join('\n');
      return SystemResponse.success(
        command: 'read_file',
        data: sliced,
      );
    }

    // Standard complete read
    final content = file.readAsStringSync();
    return SystemResponse.success(
      command: 'read_file',
      data: content,
    );
  }

  SystemResponse _handleWriteFile(Map<String, dynamic> parameters) {
    final virtualPath = parameters['path'] as String?;
    final content = parameters['content'] as String?;
    final append = parameters['append'] as bool? ?? false;

    if (virtualPath == null || virtualPath.trim().isEmpty) {
      return SystemResponse.error(
        command: 'write_file',
        errorMessage: 'Missing required parameter "path".',
      );
    }
    if (content == null) {
      return SystemResponse.error(
        command: 'write_file',
        errorMessage: 'Missing required parameter "content".',
      );
    }

    final file = fs.mounts.resolveVirtualFile(virtualPath);

    // Automatically synthesize parent directories if they don't exist
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    if (append) {
      file.writeAsStringSync(content, mode: FileMode.append);
    } else {
      file.writeAsStringSync(content, mode: FileMode.write);
    }

    return SystemResponse.success(
      command: 'write_file',
      data: 'File written successfully: "$virtualPath" (${file.lengthSync()} bytes)',
    );
  }

  SystemResponse _handleGrep(Map<String, dynamic> parameters) {
    final pattern = parameters['pattern'] as String?;
    final targetPath = (parameters['path'] as String?)?.trim() ?? 'primary';
    final recursive = parameters['recursive'] as bool? ?? true;
    final caseSensitive = parameters['case_sensitive'] as bool? ?? true;

    if (pattern == null || pattern.isEmpty) {
      return SystemResponse.error(
        command: 'grep',
        errorMessage: 'Missing required parameter "pattern".',
      );
    }

    RegExp regex;
    try {
      regex = RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      regex = RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
    }

    final filesToSearch = <File>[];

    // Check if target is a file or a directory
    try {
      final possibleFile = fs.mounts.resolveVirtualFile(targetPath);
      if (possibleFile.existsSync() && possibleFile is! Directory) {
        filesToSearch.add(possibleFile);
      }
    } catch (_) {}

    if (filesToSearch.isEmpty) {
      final dir = fs.mounts.resolveVirtualDir(targetPath);
      if (!dir.existsSync()) {
        return SystemResponse.error(
          command: 'grep',
          errorMessage: 'Path not found: "$targetPath"',
        );
      }

      for (final entity in dir.listSync(recursive: recursive)) {
        if (entity is File) {
          filesToSearch.add(entity);
        }
      }
    }

    final matches = <Map<String, dynamic>>[];

    for (final file in filesToSearch) {
      try {
        final lines = file.readAsLinesSync();
        final vPath = fs.mounts.toVirtualPath(file);

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (regex.hasMatch(line)) {
            matches.add({
              'file': vPath,
              'line': i + 1,
              'content': line.trimRight(),
            });
          }
        }
      } catch (_) {
        // Skip binary or unreadable files
      }
    }

    if (matches.isEmpty) {
      return SystemResponse.success(
        command: 'grep',
        data: 'No matches found for pattern "$pattern" in "$targetPath".',
      );
    }

    return SystemResponse.success(
      command: 'grep',
      data: matches,
    );
  }

  SystemResponse _handleGlob(Map<String, dynamic> parameters) {
    final pattern = parameters['pattern'] as String?;
    final targetPath = (parameters['path'] as String?)?.trim() ?? 'primary';

    if (pattern == null || pattern.isEmpty) {
      return SystemResponse.error(
        command: 'glob',
        errorMessage: 'Missing required parameter "pattern".',
      );
    }

    final dir = fs.mounts.resolveVirtualDir(targetPath);
    if (!dir.existsSync()) {
      return SystemResponse.error(
        command: 'glob',
        errorMessage: 'Directory not found: "$targetPath"',
      );
    }

    final globMatcher = Glob(pattern);
    final results = <String>[];

    try {
      for (final entity in globMatcher.listSync(root: dir.path)) {
        final file = File(entity.path);
        if (file.existsSync() && FileSystemEntity.isFileSync(file.path)) {
          results.add(fs.mounts.toVirtualPath(file));
        }
      }
    } catch (e) {
      return SystemResponse.error(
        command: 'glob',
        errorMessage: 'Invalid glob pattern: $e',
      );
    }

    results.sort();
    return SystemResponse.success(
      command: 'glob',
      data: results,
    );
  }

  SystemResponse _handleListDirectory(Map<String, dynamic> parameters) {
    final targetPath = (parameters['path'] as String?)?.trim() ?? 'primary';

    final dir = fs.mounts.resolveVirtualDir(targetPath);
    if (!dir.existsSync()) {
      return SystemResponse.error(
        command: 'list_directory',
        errorMessage: 'Directory not found: "$targetPath"',
      );
    }

    final entries = <Map<String, dynamic>>[];
    final list = dir.listSync(recursive: false);
    list.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    for (final entity in list) {
      final isDir = entity is Directory;
      final vPath = fs.mounts.toVirtualPath(entity);
      entries.add({
        'name': entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
        'type': isDir ? 'directory' : 'file',
        'path': vPath,
        if (!isDir && entity is File) 'size': entity.lengthSync(),
      });
    }

    return SystemResponse.success(
      command: 'list_directory',
      data: entries,
    );
  }
}
