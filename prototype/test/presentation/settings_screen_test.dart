import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/secure_storage/key_storage_service.dart';
import 'package:harness/data/services/model_download_service.dart';
import 'package:harness/presentation/bloc/model_switcher_bloc.dart';
import 'package:harness/presentation/screens/settings_screen.dart';

void main() {
  late AppDatabase db;
  late KeyStorageService keyStorage;

  setUp(() {
    db = AppDatabase.inMemory();
    keyStorage = KeyStorageService(useInMemoryFallback: true);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'SettingsScreen displays provider dropdown and shows inputs for selected provider',
    (tester) async {
      final switcherBloc = ModelSwitcherBloc(
        database: db,
        keyStorage: keyStorage,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ModelSwitcherBloc>.value(
            value: switcherBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      // Pump until BLoC completes loading
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }

      // Verify AppBar title is present
      expect(find.text('Settings'), findsOneWidget);

      // Verify default active provider (Gemini) is selected in dropdown
      expect(find.text('Gemini'), findsWidgets);
      expect(find.text('Gemini Configuration'), findsOneWidget);

      // Verify model selection controls are visible
      expect(find.text('Model Selection'), findsOneWidget);
      expect(find.text('gemini-2.0-flash'), findsWidgets);

      // Enter an API key for Gemini
      final apiKeyFinder = find.widgetWithText(TextField, 'Enter API Key');
      expect(apiKeyFinder, findsOneWidget);

      await tester.enterText(apiKeyFinder, 'test-gemini-secret-key');
      await tester.pump();

      // Tap 'Save Key'
      final saveButtonFinder = find.widgetWithText(FilledButton, 'Save Key');
      expect(saveButtonFinder, findsOneWidget);

      await tester.ensureVisible(saveButtonFinder);
      await tester.tap(saveButtonFinder);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify key is saved in keyStorage for 'gemini'
      final savedKey = await keyStorage.getApiKey('gemini');
      expect(savedKey, equals('test-gemini-secret-key'));

      // Select 'On-Device SLM' in the provider dropdown
      final providerDropdown = find
          .byType(DropdownButtonFormField<String>)
          .first;
      await tester.ensureVisible(providerDropdown);
      await tester.tap(providerDropdown);
      await tester.pumpAndSettle();

      // Tap 'On-Device SLM' item in dropdown list
      final slmItem = find.text('On-Device SLM').last;
      await tester.ensureVisible(slmItem);
      await tester.tap(slmItem);
      await tester.pumpAndSettle();

      // Inputs should update to On-Device SLM
      expect(find.text('On-Device SLM Configuration'), findsOneWidget);
      expect(find.text('On-Device Model Selection'), findsOneWidget);

      // Verify modern LiteRT-LM deployable models with tagged memory consumption
      expect(find.text('Gemma 4 (E2B)'), findsOneWidget);
      expect(find.text('~1.6 GB RAM'), findsOneWidget);

      expect(find.text('Qwen 2.5 (1.5B)'), findsOneWidget);
      expect(find.text('~1.4 GB RAM'), findsOneWidget);

      expect(find.text('DeepSeek-R1 (1.5B)'), findsOneWidget);
      expect(find.text('~1.5 GB RAM'), findsOneWidget);

      expect(find.text('Qwen 3 (0.6B)'), findsOneWidget);
      expect(find.text('~0.7 GB RAM'), findsOneWidget);

      // Clear active snackbars and unfocus
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox());
      switcherBloc.close();
    },
  );

  testWidgets(
    'On-Device SLM: initial state shows Download tag, tapping download shows determinate CircularProgressIndicator, and completed download removes download tag',
    (tester) async {
      final switcherBloc = ModelSwitcherBloc(
        database: db,
        keyStorage: keyStorage,
      );

      final fastDownloadService = ModelDownloadService(
        isSimulation: true,
        tickInterval: const Duration(milliseconds: 15),
        totalSteps: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ModelSwitcherBloc>.value(
            value: switcherBloc,
            child: SettingsScreen(downloadService: fastDownloadService),
          ),
        ),
      );

      // Settle loading
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }

      // Switch to On-Device SLM
      final providerDropdown = find
          .byType(DropdownButtonFormField<String>)
          .first;
      await tester.ensureVisible(providerDropdown);
      await tester.tap(providerDropdown);
      await tester.pumpAndSettle();

      final slmItem = find.text('On-Device SLM').last;
      await tester.ensureVisible(slmItem);
      await tester.tap(slmItem);
      await tester.pumpAndSettle();

      // Verify no models ship bundled -> download buttons exist for models
      final qwenDownloadBtn = find.byKey(
        const ValueKey('download_btn_qwen_2_5_1_5b'),
      );
      expect(qwenDownloadBtn, findsOneWidget);

      // Tap download on Qwen 2.5
      await tester.ensureVisible(qwenDownloadBtn);
      await tester.tap(qwenDownloadBtn);
      await tester.pump(const Duration(milliseconds: 20));

      // Verify determinate linear progress indicator appears tracking percentage
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Advance time until download completes (10 ticks * 15ms = 150ms)
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      await tester.pumpAndSettle();

      // Once downloaded, it shows NO tag for that (download button is gone)
      expect(
        find.byKey(const ValueKey('download_btn_qwen_2_5_1_5b')),
        findsNothing,
      );

      // Clean up
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox());
      switcherBloc.close();
    },
  );
}
