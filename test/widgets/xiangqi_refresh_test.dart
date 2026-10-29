import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  Future<void> pumpRefresh(WidgetTester tester, Future<void> Function() request, {Key? key}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: XiangqiRefreshScope(
          key: key,
          onRefresh: request,
          builder: (context, refresh, busy) => Scaffold(
            appBar: AppBar(
              actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
            ),
            body: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(children: const [Text('Loaded data')]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void testDesktop(String name, WidgetTesterCallback callback) =>
      testWidgets(name, callback, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testDesktop('mouse and pull refresh share one request and restore the button on completion', (
    tester,
  ) async {
    final response = Completer<void>();
    var calls = 0;
    await pumpRefresh(tester, () {
      calls++;
      return response.future;
    });
    final pull = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
    final first = pull();
    final second = pull();
    expect(identical(first, second), isTrue);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Loaded data'), findsOneWidget);
    expect(tester.widget<DesktopRefreshButton>(find.byType(DesktopRefreshButton)).busy, isTrue);
    response.complete();
    await first;
    await tester.pump();
    expect(tester.widget<DesktopRefreshButton>(find.byType(DesktopRefreshButton)).busy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testDesktop('a synchronously failing refresh is reported and does not stick busy', (
    tester,
  ) async {
    await pumpRefresh(tester, () => throw StateError('unavailable'));
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Loaded data'), findsOneWidget);
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(tester.widget<DesktopRefreshButton>(find.byType(DesktopRefreshButton)).busy, isFalse);
    expect(tester.takeException(), isNull);
  });

  testDesktop('disposing a refresh before its failure cannot affect the next page', (tester) async {
    final response = Completer<void>();
    await pumpRefresh(tester, () => response.future);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    response.completeError(StateError('unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testDesktop('retained data survives refresh failure but never crosses account identity', (
    tester,
  ) async {
    Object identity = 'account A';
    AsyncValue<String> value = const AsyncData('A private content');
    late StateSetter update;
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return XiangqiRetainedData(
                identity: identity,
                value: value,
                builder: (_, current) => current.when(
                  skipError: true,
                  data: Text.new,
                  loading: () => const Text('Loading'),
                  error: (_, _) => const Text('Retry'),
                ),
              );
            },
          ),
        ),
      ),
    );
    update(() {
      final failure = AsyncError<String>(StateError('unavailable'), StackTrace.current);
      // Construct Riverpod's real reload error, including its implicit previous account data.
      // ignore: invalid_use_of_internal_member
      value = failure.copyWithPrevious(value);
    });
    await tester.pump();
    expect(find.text('A private content'), findsOneWidget);
    update(() => identity = 'account B');
    await tester.pump();
    expect(find.text('A private content'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    update(() => value = const AsyncData('B private content'));
    await tester.pump();
    expect(find.text('B private content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
