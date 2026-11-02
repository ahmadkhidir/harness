import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/engine.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/modules/storage/storage_module.dart';
import 'package:harness/providers/model_provider.dart';
import 'package:path/path.dart' as p;

class ScriptedModelProvider extends ModelProvider {
  final List<String> script;
  final List<List<ModelMessage>> receivedHistories = [];
  final List<String?> receivedSystemInstructions = [];
  int _step = 0;

  ScriptedModelProvider(this.script);

  @override
  ProviderConfig get config => ProviderConfig(
        id: 'test_provider',
        providerType: 'local_device',
        displayName: 'Test LLM',
        modelName: 'test-llm-1',
      );

  @override
  Future<String> generate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async {
    receivedHistories.add(List.from(messages));
    receivedSystemInstructions.add(systemInstruction);
    if (_step < script.length) {
      return script[_step++];
    }
    return script.last;
  }

  @override
  Stream<String> streamGenerate({
    required List<ModelMessage> messages,
    String? systemInstruction,
    List<CommandDefinition>? tools,
    String? apiKey,
  }) async* {
    yield await generate(
      messages: messages,
      systemInstruction: systemInstruction,
      tools: tools,
      apiKey: apiKey,
    );
  }
}

void main() {
  group('FEAT-004 Acceptance Tests - Sandboxed Storage Inspection & Hierarchical Workspace Mapping', () {
    late Directory tempRoot;
    late HarnessFileSystem fileSystem;
    late StorageModule storageModule;
    late CommandRouter router;
    late ContextBuilder contextBuilder;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('harness_feat_004_test_');
      fileSystem = HarnessFileSystem(rootDir: tempRoot);
      fileSystem.ensureBaseDirectoriesSync();
      storageModule = StorageModule(fileSystem: fileSystem);
      router = CommandRouter()..registerModule(storageModule);
      contextBuilder = ContextBuilder();
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Scenario 1: Prompt includes virtual tree under primary without exposing host filesystem paths', () {
      // Seed files in storage directory
      final storageDir = fileSystem.storageDir;
      File(p.join(storageDir.path, 'notes.txt')).writeAsStringSync('Notes content');
      File(p.join(storageDir.path, 'report.docx')).writeAsStringSync('Report bytes');
      File(p.join(storageDir.path, 'analysis.py')).writeAsStringSync('print("Analysis")');

      final tree = fileSystem.formatFilesystemTree();

      expect(tree.contains('<filesystem>'), isTrue);
      expect(tree.contains('</filesystem>'), isTrue);
      expect(tree.contains('- primary/'), isTrue);
      expect(tree.contains('notes.txt'), isTrue);
      expect(tree.contains('report.docx'), isTrue);
      expect(tree.contains('analysis.py'), isTrue);

      // Strict Zero Host Path Leakage: Host directory path must never appear
      expect(tree.contains(storageDir.path), isFalse);
      expect(tree.contains(tempRoot.path), isFalse);
    });

    test('Scenario 2: Attached external storage folder appears as virtual volume in prompt', () {
      final externalTemp = Directory.systemTemp.createTempSync('external_downloads_');
      try {
        File(p.join(externalTemp.path, 'invoice.pdf')).writeAsStringSync('PDF data');
        File(p.join(externalTemp.path, 'dataset.csv')).writeAsStringSync('a,b,c');

        fileSystem.mounts.registerMount('downloads', externalTemp);

        final tree = fileSystem.formatFilesystemTree();

        expect(tree.contains('- downloads/'), isTrue);
        expect(tree.contains('invoice.pdf'), isTrue);
        expect(tree.contains('dataset.csv'), isTrue);

        // Strict Zero Host Path Leakage
        expect(tree.contains(externalTemp.path), isFalse);
      } finally {
        try {
          externalTemp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('Scenario 3: read_file with line-range returns only specified lines', () async {
      // Create multi-line document with 50 lines
      final storageDir = fileSystem.storageDir;
      final file = File(p.join(storageDir.path, 'notes.txt'));
      final lines = List.generate(50, (i) => 'Line ${i + 1}');
      file.writeAsStringSync(lines.join('\n'));

      final response = await storageModule.executeCommand('read_file', {
        'path': 'primary/notes.txt',
        'start_line': 10,
        'end_line': 30,
      });

      expect(response.isSuccess, isTrue);
      final content = response.data as String;
      final returnedLines = content.split('\n');

      expect(returnedLines.length, 21); // 10 through 30 inclusive = 21 lines
      expect(returnedLines.first, 'Line 10');
      expect(returnedLines.last, 'Line 30');
    });

    test('Scenario 4: grep searches pattern and returns matching lines with virtual paths and line numbers', () async {
      final srcDir = Directory(p.join(fileSystem.storageDir.path, 'src'))..createSync(recursive: true);
      File(p.join(srcDir.path, 'app.dart')).writeAsStringSync('''
void main() {
  // TODO: initialize auth service
  print('Hello');
}
''');
      File(p.join(srcDir.path, 'utils.dart')).writeAsStringSync('''
class Utils {
  // regular comment
  // TODO: optimize caching logic
}
''');

      final response = await storageModule.executeCommand('grep', {
        'pattern': 'TODO',
        'path': 'primary/src',
      });

      expect(response.isSuccess, isTrue);
      expect(response.data, isA<List>());
      final matches = response.data as List;
      expect(matches.length, 2);

      // Verify virtual paths are returned, NEVER host paths
      for (final match in matches) {
        final m = match as Map<String, dynamic>;
        expect(m['file'].toString().startsWith('primary/src'), isTrue);
        expect(m['file'].toString().contains(tempRoot.path), isFalse);
        expect(m['line'], isA<int>());
        expect(m['content'].toString().contains('TODO'), isTrue);
      }
    });

    test('Scenario 5: write_file creates file and automatically synthesizes parent directories', () async {
      final response = await storageModule.executeCommand('write_file', {
        'path': 'primary/output/subfolder/summary.md',
        'content': '# Summary Report\nGenerated autonomously.',
      });

      expect(response.isSuccess, isTrue);

      final writtenFile = File(p.join(fileSystem.storageDir.path, 'output', 'subfolder', 'summary.md'));
      expect(writtenFile.existsSync(), isTrue);
      expect(writtenFile.readAsStringSync(), '# Summary Report\nGenerated autonomously.');
    });

    test('Scenario 6: glob matches file patterns across workspace and returns virtual paths', () async {
      final storageDir = fileSystem.storageDir;
      final docsDir = Directory(p.join(storageDir.path, 'docs'))..createSync(recursive: true);

      File(p.join(storageDir.path, 'README.md')).writeAsStringSync('# Readme');
      File(p.join(docsDir.path, 'guide.md')).writeAsStringSync('# Guide');
      File(p.join(storageDir.path, 'data.json')).writeAsStringSync('{}');

      final response = await storageModule.executeCommand('glob', {
        'pattern': '**/*.md',
        'path': 'primary',
      });

      expect(response.isSuccess, isTrue);
      expect(response.data, isA<List>());
      final list = response.data as List<String>;
      expect(list.length, 2);
      expect(list, contains('primary/README.md'));
      expect(list, contains('primary/docs/guide.md'));
      expect(list.contains('primary/data.json'), isFalse);

      // Verify zero host path leakage in glob results
      for (final item in list) {
        expect(item.contains(tempRoot.path), isFalse);
      }
    });

    test('Scenario 7: list_directory returns entries with name, type, and virtual path', () async {
      final storageDir = fileSystem.storageDir;
      Directory(p.join(storageDir.path, 'subfolder')).createSync();
      File(p.join(storageDir.path, 'hello.txt')).writeAsStringSync('hello');

      final response = await storageModule.executeCommand('list_directory', {
        'path': 'primary',
      });

      expect(response.isSuccess, isTrue);
      final entries = response.data as List;
      expect(entries.length, 2);

      final subfolderEntry = entries.firstWhere((e) => e['name'] == 'subfolder');
      expect(subfolderEntry['type'], 'directory');
      expect(subfolderEntry['path'], 'primary/subfolder');

      final fileEntry = entries.firstWhere((e) => e['name'] == 'hello.txt');
      expect(fileEntry['type'], 'file');
      expect(fileEntry['path'], 'primary/hello.txt');
      expect(fileEntry['size'], 5);
    });

    test('Edge Case 1: Path traversal attack is blocked and returns access-denied error', () async {
      final response = await storageModule.executeCommand('read_file', {
        'path': 'primary/../../data/models/qwen.gguf',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage?.contains('Access denied'), isTrue);
      expect(response.errorMessage?.contains('escapes the mount sandbox'), isTrue);
    });

    test('Edge Case 2: Unknown mount tag returns descriptive error listing available volumes', () async {
      final response = await storageModule.executeCommand('read_file', {
        'path': 'unknown_vol/data.csv',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage?.contains("Unknown storage volume 'unknown_vol'"), isTrue);
      expect(response.errorMessage?.contains('Available volumes: primary'), isTrue);
    });

    test('Edge Case 3: Extremely large file read (> 1 MB) without line range truncates to 200 lines with warning', () async {
      final storageDir = fileSystem.storageDir;
      final bigFile = File(p.join(storageDir.path, 'large_log.txt'));

      // Write a file exceeding 1MB with over 300 lines
      final sink = bigFile.openWrite();
      final padding = 'A' * 4000; // ~4KB per line
      for (int i = 0; i < 300; i++) {
        sink.writeln('Line ${i + 1}: $padding');
      }
      await sink.close();

      expect(bigFile.lengthSync() > 1024 * 1024, isTrue);

      final response = await storageModule.executeCommand('read_file', {
        'path': 'primary/large_log.txt',
      });

      expect(response.isSuccess, isTrue);
      final content = response.data as String;
      expect(content.contains('[Truncated: File exceeds 1 MB limit. Showing first 200 lines. Use start_line and end_line parameters to read further.]'), isTrue);

      // Verify it contains Line 200 but not Line 201
      expect(content.contains('Line 200:'), isTrue);
      expect(content.contains('Line 201:'), isFalse);
    });

    test('End-to-End: Autonomous tool loop coordinates storage read and write through to final delivery', () async {
      // Seed input document
      File(p.join(fileSystem.storageDir.path, 'task_input.txt')).writeAsStringSync('Important task specification text.');

      final scriptedModel = ScriptedModelProvider([
        // Turn 1: Model reads task_input.txt
        '''
I need to read the task specification first.
<system_call>
{"command": "read_file", "parameters": {"path": "primary/task_input.txt"}}
</system_call>
''',
        // Turn 2: Model writes summary into output/summary.md
        '''
Now I will write the generated summary.
<system_call>
{"command": "write_file", "parameters": {"path": "primary/output/summary.md", "content": "# Summary\\nTask executed successfully."}}
</system_call>
''',
        // Turn 3: Model delivers final user message
        '''
<system_call>
{"command": "send_message", "parameters": {"text": "I have reviewed your task and written the summary to output/summary.md."}}
</system_call>
''',
      ]);

      final engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: scriptedModel,
      );

      final events = <EngineProgressEvent>[];
      await for (final event in engine.executeTurn(
        userPrompt: 'Review my task input and summarize it in output/summary.md',
        sessionId: 'sess_e2e_storage',
      )) {
        events.add(event);
      }

      final completed = events.last as EngineTurnCompleted;
      expect(completed.turn.text, 'I have reviewed your task and written the summary to output/summary.md.');
      expect(completed.turn.toolCalls.length, 2);

      expect(completed.turn.toolCalls[0].call.command, 'read_file');
      expect(completed.turn.toolCalls[0].status, 'success');
      expect(completed.turn.toolCalls[0].output, 'Important task specification text.');

      expect(completed.turn.toolCalls[1].call.command, 'write_file');
      expect(completed.turn.toolCalls[1].status, 'success');

      // Verify physical file was created in storage
      final summaryFile = File(p.join(fileSystem.storageDir.path, 'output', 'summary.md'));
      expect(summaryFile.existsSync(), isTrue);
      expect(summaryFile.readAsStringSync(), '# Summary\nTask executed successfully.');
    });
  });
}

