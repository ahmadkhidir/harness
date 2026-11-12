import 'package:harness/presentation/theme/harness_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/system_call.dart';
import 'package:harness/presentation/bloc/harness_session_state.dart';
import 'package:harness/presentation/widgets/system_call_pill.dart';

void main() {
  group('SystemCallPill Widget Tests', () {
    testWidgets('renders running indicator with circular progress indicator', (tester) async {
      final indicator = ToolExecutionIndicator(
        call: SystemCall(command: 'web_search', parameters: {}),
        status: 'running',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemCallPill(indicator: indicator),
          ),
        ),
      );

      expect(find.text('web_search'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders success indicator with check icon', (tester) async {
      final indicator = ToolExecutionIndicator(
        call: SystemCall(command: 'read_file', parameters: {}),
        status: 'success',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemCallPill(indicator: indicator),
          ),
        ),
      );

      expect(find.text('read_file'), findsOneWidget);
      expect(find.byIcon(HarnessIcons.success), findsOneWidget);
    });

    testWidgets('renders error indicator with error icon', (tester) async {
      final indicator = ToolExecutionIndicator(
        call: SystemCall(command: 'grep', parameters: {}),
        status: 'error',
        errorMessage: 'Pattern not found',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemCallPill(indicator: indicator),
          ),
        ),
      );

      expect(find.text('grep'), findsOneWidget);
      expect(find.byIcon(HarnessIcons.error), findsOneWidget);
    });
  });
}

