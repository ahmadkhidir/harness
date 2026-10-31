import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/secure_storage/key_storage_service.dart';
import 'package:harness/main.dart';
import 'package:harness/presentation/screens/chat_screen.dart';
import 'package:harness/presentation/widgets/empty_state.dart';

void main() {
  testWidgets('HarnessApp initial render smoke test', (WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    final keyStorage = KeyStorageService(useInMemoryFallback: true);

    await tester.pumpWidget(HarnessApp(
      database: database,
      keyStorage: keyStorage,
    ));
    await tester.pump();

    // Verify ChatScreen mounts as the initial route
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Harness'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Welcome to Harness'), findsOneWidget);
    expect(find.text('Ask Harness or give a task...'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // Clean up focus and timers
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  });
}
