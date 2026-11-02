import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/models.dart';
import 'package:harness/presentation/widgets/tool_calls_bottom_sheet.dart';

void main() {
  group('ToolCallsBottomSheet Widget Tests', () {
    testWidgets('renders empty state when toolCalls is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolCallsBottomSheet(toolCalls: []),
          ),
        ),
      );

      expect(find.text('Tool Executions'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('No tools were dispatched in this turn.'), findsOneWidget);
    });

    testWidgets('renders running, success, and error tool calls with details',
        (tester) async {
      final records = [
        ToolExecutionRecord(
          call: SystemCall(
            command: 'load_skill',
            parameters: const {'skill_name': 'story_writer'},
          ),
          status: 'running',
        ),
        ToolExecutionRecord(
          call: SystemCall(
            command: 'read_file',
            parameters: const {'path': 'workspace/notes.txt'},
          ),
          status: 'success',
          output: 'Notes content here',
        ),
        ToolExecutionRecord(
          call: SystemCall(
            command: 'web_search',
            parameters: const {'query': 'Flutter'},
          ),
          status: 'error',
          errorMessage: 'Network timeout',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolCallsBottomSheet(toolCalls: records),
          ),
        ),
      );

      expect(find.text('Tool Executions'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Verify first command items
      expect(find.text('load_skill'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.textContaining('story_writer'), findsOneWidget);

      expect(find.text('read_file'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);
      expect(find.textContaining('workspace/notes.txt'), findsOneWidget);
      expect(find.textContaining('Notes content here'), findsOneWidget);

      // Scroll to view the 3rd tool call item (use pump instead of pumpAndSettle due to CircularProgressIndicator)
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('web_search'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('Flutter'), findsOneWidget);
      expect(find.textContaining('Network timeout'), findsOneWidget);
    });
  });
}
