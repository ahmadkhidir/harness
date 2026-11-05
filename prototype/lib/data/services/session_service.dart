import 'dart:convert';
import 'dart:io';
import '../../core/models/context_line.dart';
import '../../core/models/session.dart';
import '../../core/models/turn.dart';
import '../../core/utils/file_system_manager.dart';
import '../database/app_database.dart';

/// Service managing isolated dual-file session threads and context compaction.
///
/// Implements FEAT-005:
/// - Maintains session threads under `<HarnessRoot>/sessions/<session_id>/`.
/// - Synchronous dual-write on turn completion: `turns.json` (authoritative UI log)
///   and `context.txt` (line-oriented transcript).
/// - Automated background compaction: summarizes older history lines into a `SUMMARY:`
///   block at line 1 when `context.txt` exceeds [compactionThresholdBytes], using atomic file
///   writes (`.tmp` -> rename) to prevent corruption.
/// - Preserves 100% of chat turns in `turns.json` across compactions.
class SessionService {
  final HarnessFileSystem? fileSystem;
  final AppDatabase? database;

  /// Byte size threshold for triggering automated background compaction (defaults to 50 KB = 51,200 bytes).
  final int compactionThresholdBytes;

  SessionService({
    this.fileSystem,
    this.database,
    this.compactionThresholdBytes = 50 * 1024,
  });

  HarnessFileSystem get fs {
    if (fileSystem != null) return fileSystem!;
    if (HarnessFileSystem.instance != null) return HarnessFileSystem.instance!;
    final temp = Directory.systemTemp.createTempSync('harness_fallback_');
    final fallbackFs = HarnessFileSystem(rootDir: Directory('${temp.path}/Harness'));
    fallbackFs.ensureBaseDirectoriesSync();
    return fallbackFs;
  }
  AppDatabase get db => database ?? AppDatabase();

  /// Creates a new isolated session workspace folder under `<HarnessRoot>/sessions/<id>/`.
  ///
  /// Synthesizes an empty `turns.json` with initial [Session] metadata and an empty `context.txt`.
  /// Sets the new session as the active session.
  Future<Session> createSession({String? id, String? title}) async {
    final now = DateTime.now().toUtc();
    final effectiveId = id ?? 'sess_${now.millisecondsSinceEpoch}';
    final effectiveTitle = (title != null && title.trim().isNotEmpty)
        ? (title.length > 128 ? title.substring(0, 128) : title.trim())
        : 'New Session';

    final sessionDir = fs.sessionDir(effectiveId);
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }

    final contextFile = fs.sessionContextFile(effectiveId);
    if (!contextFile.existsSync()) {
      contextFile.writeAsStringSync('');
    }

    final session = Session(
      id: effectiveId,
      title: effectiveTitle,
      createdAt: now,
      updatedAt: now,
      totalTurns: 0,
      contextSizeBytes: 0,
      compactionCount: 0,
      lastCompactedAt: null,
    );

    final turnsFile = fs.sessionTurnsFile(effectiveId);
    final payload = {
      'session': session.toJson(),
      'turns': <Map<String, dynamic>>[],
    };

    _atomicWriteJson(turnsFile, payload);
    await setActiveSessionId(effectiveId);
    return session;
  }

  /// Retrieves all session workspaces ordered by `updatedAt` descending.
  Future<List<Session>> getAllSessions() async {
    final sessionsDir = fs.sessionsDir;
    if (!sessionsDir.existsSync()) {
      return [];
    }

    final sessions = <Session>[];
    final entities = sessionsDir.listSync(recursive: false);

    for (final entity in entities) {
      if (entity is Directory) {
        final sessionId = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        try {
          final session = await getSession(sessionId);
          if (session != null) {
            sessions.add(session);
          }
        } catch (_) {}
      }
    }

    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  /// Retrieves a specific [Session] by its [sessionId].
  Future<Session?> getSession(String sessionId) async {
    final turnsFile = fs.sessionTurnsFile(sessionId);
    if (!turnsFile.existsSync()) {
      return null;
    }

    try {
      final raw = turnsFile.readAsStringSync();
      final decoded = json.decode(raw);
      final contextFile = fs.sessionContextFile(sessionId);
      final actualSizeBytes = contextFile.existsSync() ? contextFile.lengthSync() : 0;

      if (decoded is Map<String, dynamic> && decoded.containsKey('session')) {
        final session = Session.fromJson(decoded['session'] as Map<String, dynamic>);
        if (session.contextSizeBytes != actualSizeBytes) {
          return session.copyWith(contextSizeBytes: actualSizeBytes);
        }
        return session;
      } else if (decoded is List) {
        // Fallback: turns.json is raw list of turns without metadata envelope
        final turns = decoded
            .map((t) => Turn.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList();
        final stat = turnsFile.statSync();
        return Session(
          id: sessionId,
          title: 'Session $sessionId',
          createdAt: stat.changed.toUtc(),
          updatedAt: turns.isNotEmpty ? turns.last.timestamp.toUtc() : stat.modified.toUtc(),
          totalTurns: turns.length,
          contextSizeBytes: actualSizeBytes,
          compactionCount: 0,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves the active session ID pointer.
  Future<String?> getActiveSessionId() async {
    final activeId = await db.getActiveSessionId();
    if (activeId != null && activeId.isNotEmpty) {
      fs.activeSessionId = activeId;
      return activeId;
    }
    return fs.activeSessionId;
  }

  /// Updates the active session ID pointer in storage and runtime filesystem manager.
  Future<void> setActiveSessionId(String sessionId) async {
    await db.setActiveSessionId(sessionId);
    fs.activeSessionId = sessionId;
  }

  /// Loads conversational turns from `turns.json` for the given [sessionId].
  Future<List<Turn>> loadTurns(String sessionId) async {
    final turnsFile = fs.sessionTurnsFile(sessionId);
    if (!turnsFile.existsSync()) {
      return [];
    }

    try {
      final raw = turnsFile.readAsStringSync();
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic> && decoded.containsKey('turns')) {
        final turnsList = decoded['turns'] as List;
        return turnsList
            .map((t) => Turn.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList();
      } else if (decoded is List) {
        return decoded
            .map((t) => Turn.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Performs a synchronous dual-write across `turns.json` and `context.txt`.
  ///
  /// Appends [turn] to `turns.json` (authoritative UI log) and formats a corresponding
  /// [ContextLine] into `context.txt` (`USER:`, `AGENT:`). Updates session metadata on disk.
  Future<void> appendTurn(String sessionId, Turn turn) async {
    final sessionDir = fs.sessionDir(sessionId);
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }

    final turnsFile = fs.sessionTurnsFile(sessionId);
    final contextFile = fs.sessionContextFile(sessionId);

    // 1. Dual-write to context.txt
    ContextLine contextLine;
    if (turn.isUser) {
      contextLine = ContextLine(
        type: ContextLineType.user,
        content: turn.text ?? '',
      );
    } else {
      if (turn.isA2UI && (turn.text == null || turn.text!.trim().isEmpty)) {
        contextLine = ContextLine(
          type: ContextLineType.agent,
          content: ContextLine.formatA2UIStub(
            surfaceId: turn.a2uiSurfaceId ?? 'default',
            rootComponentType: 'surface',
          ),
        );
      } else {
        contextLine = ContextLine(
          type: ContextLineType.agent,
          content: turn.text ?? '',
        );
      }
    }

    // Append discrete line to context.txt
    contextFile.writeAsStringSync(
      contextLine.format(),
      mode: FileMode.append,
      flush: true,
    );

    // 2. Dual-write to turns.json
    final existingTurns = await loadTurns(sessionId);
    final updatedTurns = List<Turn>.from(existingTurns)..add(turn);

    Session currentSession = (await getSession(sessionId)) ??
        Session(
          id: sessionId,
          title: 'Session $sessionId',
          createdAt: turn.timestamp.toUtc(),
          updatedAt: turn.timestamp.toUtc(),
          totalTurns: 0,
          contextSizeBytes: 0,
        );

    final updatedSession = currentSession.copyWith(
      totalTurns: updatedTurns.length,
      updatedAt: turn.timestamp.toUtc(),
      contextSizeBytes: contextFile.existsSync() ? contextFile.lengthSync() : 0,
    );

    final payload = {
      'session': updatedSession.toJson(),
      'turns': updatedTurns.map((t) => t.toJson()).toList(),
    };

    _atomicWriteJson(turnsFile, payload);
    fs.activeSessionId = sessionId;
  }

  /// Appends a turn to `turns.json` (UI) without touching `context.txt`.
  ///
  /// User prompts use this before dispatch; their context line is written after
  /// the model request starts.
  Future<void> appendUiTurn(String sessionId, Turn turn) async {
    final sessionDir = fs.sessionDir(sessionId);
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }

    final existingTurns = await loadTurns(sessionId);
    final updatedTurns = List<Turn>.from(existingTurns)..add(turn);
    final contextFile = fs.sessionContextFile(sessionId);

    final currentSession = (await getSession(sessionId)) ??
        Session(
          id: sessionId,
          title: 'Session $sessionId',
          createdAt: turn.timestamp.toUtc(),
          updatedAt: turn.timestamp.toUtc(),
          totalTurns: 0,
          contextSizeBytes: 0,
        );

    final updatedSession = currentSession.copyWith(
      totalTurns: updatedTurns.length,
      updatedAt: turn.timestamp.toUtc(),
      contextSizeBytes:
          contextFile.existsSync() ? contextFile.lengthSync() : 0,
    );

    _atomicWriteJson(fs.sessionTurnsFile(sessionId), {
      'session': updatedSession.toJson(),
      'turns': updatedTurns.map((item) => item.toJson()).toList(),
    });
    fs.activeSessionId = sessionId;
  }

  /// Appends a single line to `context.txt` and refreshes session metadata.
  Future<void> appendContextLine(String sessionId, ContextLine line) async {
    final sessionDir = fs.sessionDir(sessionId);
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }

    final contextFile = fs.sessionContextFile(sessionId);
    contextFile.writeAsStringSync(
      line.format(),
      mode: FileMode.append,
      flush: true,
    );

    final turns = await loadTurns(sessionId);
    final currentSession = (await getSession(sessionId)) ??
        Session(
          id: sessionId,
          title: 'Session $sessionId',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          totalTurns: turns.length,
          contextSizeBytes: 0,
        );

    final updatedSession = currentSession.copyWith(
      updatedAt: DateTime.now().toUtc(),
      contextSizeBytes: contextFile.lengthSync(),
    );

    _atomicWriteJson(fs.sessionTurnsFile(sessionId), {
      'session': updatedSession.toJson(),
      'turns': turns.map((item) => item.toJson()).toList(),
    });
    fs.activeSessionId = sessionId;
  }

  /// Appends a `USER:` line after a prompt has been dispatched to the model.
  Future<void> appendUserContextLine(String sessionId, String prompt) {
    return appendContextLine(
      sessionId,
      ContextLine(type: ContextLineType.user, content: prompt),
    );
  }

  /// Appends a `TOOL:` line describing a completed tool call.
  ///
  /// Parameters, errors, and outputs are truncated so one verbose tool result
  /// cannot dominate the transcript that is sent on the next turn.
  Future<void> appendToolObservation(
    String sessionId, {
    required String command,
    required Map<String, dynamic> parameters,
    required bool success,
    String? error,
    dynamic output,
  }) async {
    var truncated = false;

    String clip(String text, int max) {
      if (text.length <= max) return text;
      truncated = true;
      return '${text.substring(0, max)}…';
    }

    String encode(dynamic value) {
      if (value is String) return value;
      try {
        return jsonEncode(value);
      } catch (_) {
        return value.toString();
      }
    }

    final encodedParameters = _encodeParameters(parameters);
    final parameterValue = encodedParameters.length <= 1000
        ? parameters
        : clip(encodedParameters, 1000);

    final payload = <String, dynamic>{
      'command': command,
      'parameters': parameterValue,
      'status': success ? 'success' : 'error',
      if (error != null) 'error': clip(error, 2000),
      if (output != null) 'output': clip(encode(output), 3000),
      'truncated': truncated,
    };

    await appendContextLine(
      sessionId,
      ContextLine(type: ContextLineType.tool, content: jsonEncode(payload)),
    );
  }

  /// Reads the session transcript for model injection.
  ///
  /// When [excludePrompt] is supplied, a trailing `USER:` line that exactly
  /// matches it is removed defensively (the current prompt is appended only
  /// after dispatch in the normal flow).
  Future<String> readContextTranscript(
    String sessionId, {
    String? excludePrompt,
  }) async {
    final contextFile = fs.sessionContextFile(sessionId);
    if (!contextFile.existsSync()) return '';

    final lines = contextFile
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (excludePrompt != null && lines.isNotEmpty) {
      final expected = 'USER: ${ContextLine.sanitizeText(excludePrompt)}';
      if (lines.last.trim() == expected) {
        lines.removeLast();
      }
    }

    return lines.join('\n').trim();
  }

  /// Renames an existing session, updating its title in `turns.json`.
  Future<Session> renameSession(String sessionId, String newTitle) async {
    final turnsFile = fs.sessionTurnsFile(sessionId);
    final session = await getSession(sessionId);
    if (session == null) {
      throw ArgumentError('Session "$sessionId" does not exist.');
    }

    final cleanTitle = newTitle.trim().isEmpty ? 'Untitled Session' : newTitle.trim();
    final validatedTitle = cleanTitle.length > 128 ? cleanTitle.substring(0, 128) : cleanTitle;

    final updatedSession = session.copyWith(
      title: validatedTitle,
      updatedAt: DateTime.now().toUtc(),
    );

    final turns = await loadTurns(sessionId);
    final payload = {
      'session': updatedSession.toJson(),
      'turns': turns.map((t) => t.toJson()).toList(),
    };

    _atomicWriteJson(turnsFile, payload);
    return updatedSession;
  }

  /// Deletes a session and its isolated folder from disk.
  Future<void> deleteSession(String sessionId) async {
    final sessionDir = fs.sessionDir(sessionId);
    if (sessionDir.existsSync()) {
      sessionDir.deleteSync(recursive: true);
    }

    final activeId = await getActiveSessionId();
    if (activeId == sessionId) {
      final remaining = await getAllSessions();
      if (remaining.isNotEmpty) {
        await setActiveSessionId(remaining.first.id);
      } else {
        await createSession(title: 'New Session');
      }
    }
  }

  /// Checks if `context.txt` exceeds [thresholdBytes] (or the default
  /// [compactionThresholdBytes]) and triggers background compaction if needed.
  Future<bool> checkAndCompact(
    String sessionId, {
    int? thresholdBytes,
  }) async {
    final contextFile = fs.sessionContextFile(sessionId);
    if (!contextFile.existsSync()) return false;

    final size = contextFile.lengthSync();
    final limit = thresholdBytes ?? compactionThresholdBytes;
    if (size > limit) {
      return await compactSession(sessionId);
    }
    return false;
  }

  /// Summarizes older dialogue lines in `context.txt` into a consolidated `SUMMARY:` block at line 1.
  ///
  /// Retains the most recent [keepRecentLines] dialogue lines while summarizing older turns.
  /// Employs atomic file writing (`.tmp` file followed by rename) to guarantee resistance
  /// to app crashes or premature termination. Completely preserves `turns.json`.
  Future<bool> compactSession(String sessionId, {int keepRecentLines = 20}) async {
    final contextFile = fs.sessionContextFile(sessionId);
    if (!contextFile.existsSync()) return false;

    final rawContent = contextFile.readAsStringSync();
    if (rawContent.trim().isEmpty) return false;

    final allLines = rawContent
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (allLines.length <= 1) return false;

    // Retain recent dialogue lines
    final linesToKeep = keepRecentLines.clamp(1, allLines.length - 1);
    final olderLines = allLines.sublist(0, allLines.length - linesToKeep);
    final recentLines = allLines.sublist(allLines.length - linesToKeep);

    // Summarize older lines into a single coherent paragraph
    final summaryPieces = <String>[];
    for (final line in olderLines) {
      try {
        final parsed = ContextLine.parse(line);
        if (parsed.type == ContextLineType.summary) {
          summaryPieces.add(parsed.content);
        } else if (parsed.type == ContextLineType.user) {
          summaryPieces.add('User asked: "${parsed.content}".');
        } else if (parsed.type == ContextLineType.agent) {
          final snippet = parsed.content.length > 80
              ? '${parsed.content.substring(0, 80)}...'
              : parsed.content;
          summaryPieces.add('Agent replied: "$snippet".');
        } else if (parsed.type == ContextLineType.tool) {
          summaryPieces.add(_summarizeToolLine(parsed.content));
        }
      } catch (_) {
        summaryPieces.add(line.trim());
      }
    }

    var consolidatedSummary = summaryPieces.join(' ').trim();
    // Repeated compaction must not let the SUMMARY line grow without bound.
    const maxSummaryChars = 8000;
    if (consolidatedSummary.length > maxSummaryChars) {
      consolidatedSummary =
          '…${consolidatedSummary.substring(consolidatedSummary.length - maxSummaryChars)}';
    }
    final buffer = StringBuffer();
    buffer.write(ContextLine(
      type: ContextLineType.summary,
      content: consolidatedSummary,
    ).format());

    for (final r in recentLines) {
      buffer.writeln(r);
    }

    final compactedContent = buffer.toString();

    // Atomic write to context.txt (write to .tmp then rename)
    final tmpContextFile = File('${contextFile.path}.tmp');
    tmpContextFile.writeAsStringSync(compactedContent, flush: true);
    tmpContextFile.renameSync(contextFile.path);

    // Update session compaction statistics in turns.json
    final session = await getSession(sessionId);
    if (session != null) {
      final updatedSession = session.copyWith(
        compactionCount: session.compactionCount + 1,
        lastCompactedAt: DateTime.now().toUtc(),
        contextSizeBytes: contextFile.lengthSync(),
      );

      final turns = await loadTurns(sessionId);
      final payload = {
        'session': updatedSession.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
      };

      final turnsFile = fs.sessionTurnsFile(sessionId);
      _atomicWriteJson(turnsFile, payload);
    }

    return true;
  }

  /// Builds a short human-readable summary for a `TOOL:` line.
  String _summarizeToolLine(String content) {
    try {
      final data = jsonDecode(content);
      if (data is Map) {
        final command = data['command'] ?? 'tool';
        final status = data['status'] ?? 'finished';
        final detail =
            (data['error'] ?? data['output'] ?? '').toString().trim();
        final snippet = detail.length > 120
            ? '${detail.substring(0, 120)}...'
            : detail;
        return snippet.isEmpty
            ? 'Tool $command $status.'
            : 'Tool $command $status: $snippet.';
      }
    } catch (_) {}
    return 'Tool: $content';
  }

  /// Encodes tool parameters as compact JSON for a `TOOL:` line.
  String _encodeParameters(Map<String, dynamic> parameters) {
    try {
      return jsonEncode(parameters);
    } catch (_) {
      return parameters.toString();
    }
  }

  /// Writes JSON content to [targetFile] atomically using a temporary file and atomic rename.
  void _atomicWriteJson(File targetFile, Map<String, dynamic> data) {
    final tmpFile = File('${targetFile.path}.tmp');
    final encoded = json.encode(data);
    tmpFile.writeAsStringSync(encoded, flush: true);
    tmpFile.renameSync(targetFile.path);
  }
}
