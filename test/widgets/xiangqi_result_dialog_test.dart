import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_result_dialog.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('online result actions activate after one second and use the shared shell', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XiangqiResultDialog(
            title: 'Victory',
            score: '1 - 0',
            explanation: 'Checkmate',
            activationDelay: const Duration(seconds: 1),
            actionsBuilder: (context, enabled) => [
              TextButton(onPressed: enabled ? () => calls++ : null, child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await tester.pump(const Duration(milliseconds: 999));
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 401));
    await tester.tap(find.text('Close'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a delayed dialog cancels its activation timer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: XiangqiResultDialog(
          title: 'Game over',
          score: '0 - 1',
          explanation: 'Timeout',
          activationDelay: const Duration(seconds: 1),
          actionsBuilder: (_, _) => [],
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
