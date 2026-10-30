import 'package:flutter_test/flutter_test.dart';
import 'package:harness/main.dart';

void main() {
  testWidgets('HarnessApp initial render smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HarnessApp());
    expect(find.text('Harness Prototype'), findsOneWidget);
  });
}
