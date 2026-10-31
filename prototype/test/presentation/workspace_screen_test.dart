import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/skills_service.dart';
import 'package:harness/presentation/screens/workspace_screen.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late HarnessFileSystem fs;
  late SkillsService skillsService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('harness_workspace_ui_test_');
    db = AppDatabase.inMemory();
    fs = await HarnessFileSystem.init(tempDir, db);
    skillsService = SkillsService(fileSystem: fs);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: WorkspaceScreen(
        fileSystem: fs,
        skillsService: skillsService,
      ),
    );
  }

  testWidgets('WorkspaceScreen initial render displays app bar and tabs',
      (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Workspace & Skills'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    expect(find.text('Storage Files'), findsOneWidget);
    expect(find.text('Installed Skills'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Storage Files tab displays empty state when storage directory has no files',
      (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('No files in storage'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // Search bar

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Storage Files tab lists files and opens preview sheet with line numbers',
      (tester) async {
    // Create files in storage
    final file1 = File(p.join(fs.storageDir.path, 'notes.txt'));
    file1.writeAsStringSync('Line 1: Hello\nLine 2: World\nLine 3: Test');

    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.textContaining('primary/notes.txt'), findsOneWidget);

    // Tap the file to open preview sheet
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();

    // Verify preview sheet contents
    expect(find.text('Line 1: Hello'), findsOneWidget);
    expect(find.text('Line 2: World'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // Line number 1
    expect(find.byTooltip('Copy Virtual Path'), findsOneWidget);

    // Close preview sheet
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Line 1: Hello'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Installed Skills tab shows empty state when zero skills exist',
      (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Switch to Installed Skills tab
    await tester.tap(find.text('Installed Skills'));
    await tester.pumpAndSettle();

    expect(find.text('No skills installed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Installed Skills tab shows skill cards and details sheet with markdown',
      (tester) async {
    // 1. Create a valid skill
    final skillDir = Directory(p.join(fs.skillsDir.path, 'summarizer'))..createSync(recursive: true);
    File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: summarizer
description: Summarizes text into concise bullet points
version: 1.0.0
---
# Summarizer Instructions
Extract all major arguments.
''');

    // Add an auxiliary file
    final refDir = Directory(p.join(skillDir.path, 'references'))..createSync(recursive: true);
    File(p.join(refDir.path, 'guide.md')).writeAsStringSync('Guide content');

    // 2. Create a malformed skill missing SKILL.md
    Directory(p.join(fs.skillsDir.path, 'broken-package')).createSync(recursive: true);

    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();
    // Switch to Installed Skills tab
    await tester.tap(find.text('Installed Skills'));
    await tester.pumpAndSettle();

    // Verify valid skill card
    expect(find.text('summarizer'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('Summarizes text into concise bullet points'), findsOneWidget);
    expect(find.text('1 auxiliary file'), findsOneWidget);

    // Verify malformed skill card
    expect(find.text('broken-package'), findsOneWidget);
    expect(find.text('Missing SKILL.md'), findsOneWidget);

    // Tap the valid skill card to open detail sheet
    await tester.tap(find.text('summarizer'));
    await tester.pumpAndSettle();

    // Verify details sheet header and markdown instructions
    expect(find.text('SKILL.md Instructions'), findsOneWidget);
    expect(find.textContaining('Extract all major arguments'), findsOneWidget);
    expect(find.text('Auxiliary Files (1)'), findsOneWidget);
    expect(find.text('references/guide.md'), findsOneWidget);

    // Close detail sheet
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
  });
}

