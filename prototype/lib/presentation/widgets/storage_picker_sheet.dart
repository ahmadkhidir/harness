import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/file_system_manager.dart';

/// Shows a storage browser and returns the selected virtual path.
///
/// Folders return a trailing slash (for example `primary/projects/`); files
/// return their full virtual path (for example `primary/projects/plan.md`).
Future<String?> showStoragePickerSheet(
  BuildContext context,
  HarnessFileSystem fileSystem,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _StoragePickerSheet(fileSystem: fileSystem),
    ),
  );
}

class _StoragePickerSheet extends StatefulWidget {
  final HarnessFileSystem fileSystem;

  const _StoragePickerSheet({required this.fileSystem});

  @override
  State<_StoragePickerSheet> createState() => _StoragePickerSheetState();
}

class _StoragePickerSheetState extends State<_StoragePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String? _mountTag;
  String _relativePath = '';
  String _query = '';
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _atRoot => _mountTag == null;

  String get _currentVirtualPath {
    final tag = _mountTag;
    if (tag == null) return '';
    if (_relativePath.isEmpty) return '$tag/';
    return '$tag/$_relativePath/';
  }

  String _joinPath(String name) {
    if (_relativePath.isEmpty) return name;
    return '$_relativePath/$name';
  }

  List<_PickerEntry> _entries() {
    if (_atRoot) {
      return widget.fileSystem.mounts.mountTags
          .map((tag) => _PickerEntry(name: tag, isDirectory: true))
          .toList();
    }

    final entries = <_PickerEntry>[];
    try {
      final directory = widget.fileSystem.mounts.resolveVirtualDir(
        _relativePath.isEmpty ? _mountTag! : '$_mountTag/$_relativePath',
      );
      for (final entity in directory.listSync()) {
        if (entity is Link) continue;
        final name = p.basename(entity.path);
        if (entity is Directory) {
          entries.add(_PickerEntry(name: name, isDirectory: true));
        } else if (entity is File) {
          entries.add(_PickerEntry(name: name, isDirectory: false));
        }
      }
    } catch (e) {
      _error = 'Could not read this folder: $e';
      return const [];
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where((entry) => entry.name.toLowerCase().contains(query))
        .toList();
  }

  void _openDirectory(String name) {
    setState(() {
      if (_atRoot) {
        _mountTag = name;
        _relativePath = '';
      } else {
        _relativePath = _joinPath(name);
      }
      _query = '';
      _searchController.clear();
      _error = null;
    });
  }

  void _goBack() {
    if (_atRoot) return;
    setState(() {
      if (_relativePath.isEmpty) {
        _mountTag = null;
      } else {
        final separator = _relativePath.lastIndexOf('/');
        _relativePath = separator == -1
            ? ''
            : _relativePath.substring(0, separator);
      }
      _query = '';
      _searchController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries();
    final title = _atRoot
        ? 'Storage volumes'
        : (_relativePath.isEmpty
            ? _mountTag!
            : '$_mountTag/$_relativePath');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _atRoot ? null : _goBack,
              ),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (!_atRoot)
                TextButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Use this folder'),
                  onPressed: () =>
                      Navigator.of(context).pop(_currentVirtualPath),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Filter this folder',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _atRoot ? 'No storage volumes registered.' : 'This folder is empty.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      leading: Icon(
                        entry.isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(entry.name),
                      subtitle: entry.isDirectory ? null : const Text('File'),
                      onTap: () {
                        if (entry.isDirectory) {
                          _openDirectory(entry.name);
                        } else {
                          final path = _joinPath(entry.name);
                          Navigator.of(context)
                              .pop('$_mountTag/$path');
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PickerEntry {
  final String name;
  final bool isDirectory;

  const _PickerEntry({required this.name, required this.isDirectory});
}
