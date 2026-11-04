import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/skill_metadata.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/presentation/widgets/skill_picker_sheet.dart';
import 'package:harness/presentation/widgets/storage_picker_sheet.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('skill picker lists and returns the chosen skill', (tester) async {
    SkillMetadata? selected;
    final skill = SkillMetadata(
      name: 'greetings',
      description: 'Greet the user',
      version: '1.0.0',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  selected = await showSkillPickerSheet(context, [skill]);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('/greetings'), findsOneWidget);
    await tester.tap(find.text('/greetings'));
    await tester.pumpAndSettle();

    expect(selected?.name, 'greetings');
  });

  testWidgets('storage picker navigates and returns a file path', (tester) async {
    // Real filesystem work must run outside the fake-async test zone.
    late Directory tempDir;
    late HarnessFileSystem fileSystem;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('harness_picker_');
      fileSystem = HarnessFileSystem(rootDir: tempDir);
      fileSystem.ensureBaseDirectoriesSync();
      final projectDir =
          Directory(p.join(fileSystem.storageDir.path, 'projects'));
      await projectDir.create(recursive: true);
      await File(p.join(projectDir.path, 'plan.md')).writeAsString('# Plan');
    });

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  selected =
                      await showStoragePickerSheet(context, fileSystem);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('primary'), findsOneWidget);
    await tester.tap(find.text('primary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('projects'), findsOneWidget);
    await tester.tap(find.text('projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('plan.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(selected, 'primary/projects/plan.md');

    await tester.runAsync(() async {
      HarnessFileSystem.instance = null;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
  });
}
