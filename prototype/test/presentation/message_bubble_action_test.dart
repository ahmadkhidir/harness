import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/presentation/widgets/message_bubble.dart';

void main() {
  Turn actionTurn(String label) => Turn(
        id: 'turn_action_test',
        sessionId: 'sess_test',
        timestamp: DateTime.now().toUtc(),
        sender: 'user',
        contentType: 'action',
        text: label,
      );

  testWidgets('renders an action receipt instead of a typed message',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(turn: actionTurn('View tailored resume')),
        ),
      ),
    );

    expect(find.text('View tailored resume'), findsOneWidget);
    expect(find.byIcon(Icons.touch_app), findsOneWidget);
    expect(find.text('You'), findsNothing);
    expect(find.textContaining('Selected data'), findsNothing);
  });
}
