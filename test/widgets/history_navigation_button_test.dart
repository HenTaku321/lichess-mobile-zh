import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/history_navigation_button.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  Future<void> pumpHistory(WidgetTester tester, VoidCallback? onTap) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Center(child: HistoryNavigationButton(forward: false, onTap: onTap)),
        ),
      ),
    );
  }

  testWidgets('disposing a held history button cancels its delayed repeat callbacks', (
    tester,
  ) async {
    var calls = 0;
    await pumpHistory(tester, () => calls++);
    final endPress = tester
        .widget<GestureDetector>(
          find.byWidgetPredicate(
            (widget) => widget is GestureDetector && widget.onLongPress != null,
          ),
        )
        .onLongPressUp!;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(CupertinoIcons.chevron_back)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, greaterThan(0));
    final beforeDispose = calls;
    addTearDown(() async {
      // Drain the red baseline's delayed Future as well, without leaving a periodic timer behind.
      endPress();
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 210));
    expect(calls, beforeDispose);
    expect(tester.takeException(), isNull);
  });

  testWidgets('releasing a history hold stops repetition without a trailing step', (tester) async {
    var calls = 0;
    await pumpHistory(tester, () => calls++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(CupertinoIcons.chevron_back)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    final afterRelease = calls;
    await tester.pump(const Duration(seconds: 1));
    expect(calls, afterRelease);
    expect(tester.takeException(), isNull);
  });
}
