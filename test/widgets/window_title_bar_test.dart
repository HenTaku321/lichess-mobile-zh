import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/service/window_service.dart';
import 'package:lichess_mobile/src/widgets/window_title_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../service/fake_window_manager.dart';

/// The title bar on its own, over a fresh service and a mock of the window channel.
///
/// No `builder: buildAppWindow` here: this is the strip as the app mounts it, and how the app is
/// wrapped around it is `buildAppWindow`'s own test below.
Future<void> pumpTitleBar(WidgetTester tester, WindowService service) => tester.pumpWidget(
  ProviderScope(
    overrides: [windowServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(home: Scaffold(body: WindowTitleBar())),
  ),
);

/// The whole app as the desktop gets it: the window's own builder over a page.
Future<void> pumpApp(
  WidgetTester tester,
  WindowService service, {
  required TargetPlatform platform,
  Widget home = const Text('the app'),
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [windowServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      builder: buildAppWindow,
      home: home,
    ),
  ),
);

/// The strip's drag area, told apart from every other gesture detector by the pan it listens for —
/// the one that asks the compositor to move the window.
final dragArea = find.byWidgetPredicate(
  (widget) => widget is GestureDetector && widget.onPanStart != null,
);

void main() {
  TestLichessBinding.ensureInitialized();

  late FakeWindowChannel channel;
  late WindowService service;

  setUp(() {
    // The plugin flips its own maximized state when asked to maximize, and the app asks before it
    // toggles: without this the second tap on the same button would maximize again instead of
    // restoring.
    channel = FakeWindowChannel()..followMaximizeCalls();
    service = WindowService();
    addTearDown(() {
      channel.uninstall();
      testBinding.reset();
    });
  });

  group('WindowTitleBar', () {
    testWidgets('is the thin strip the window was left without, and names its buttons', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTitleBar(tester, service);

      expect(tester.getSize(find.byType(WindowTitleBar)).height, kWindowTitleBarHeight);
      expect(kWindowTitleBarHeight, 36.0);
      expect(find.text('Lichess'), findsOneWidget);

      // Named for whatever reads the screen instead of the icons: the strip sits above the app's
      // only overlay, so there is no tooltip to hover.
      expect(find.bySemanticsLabel('Minimize'), findsOneWidget);
      expect(find.bySemanticsLabel('Maximize'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('minimize, maximize and close go to the window', (tester) async {
      await pumpTitleBar(tester, service);

      await tester.tap(find.byIcon(Icons.minimize));
      await tester.pump();
      expect(channel.methods, contains('minimize'));

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      expect(channel.methods, contains('maximize'));
      expect(service.maximized.value, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(channel.methods, contains('close'));
    });

    testWidgets('the second tap on the same button restores', (tester) async {
      await pumpTitleBar(tester, service);

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      expect(service.maximized.value, isTrue);

      await tester.tap(find.byIcon(Icons.restore));
      await tester.pumpAndSettle();

      expect(channel.methods.where((method) => method == 'unmaximize'), hasLength(1));
      expect(service.maximized.value, isFalse);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);
    });

    testWidgets('follows the window being maximized from outside the app', (tester) async {
      await pumpTitleBar(tester, service);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);

      // What the plugin reports when the desktop's own gesture or shortcut maximizes the window.
      service.onWindowMaximize();
      await tester.pump();

      expect(find.byIcon(Icons.restore), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsNothing);

      service.onWindowUnmaximize();
      await tester.pump();

      expect(find.byIcon(Icons.crop_square), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsNothing);
    });

    testWidgets('dragging the strip asks the compositor to move the window', (tester) async {
      await pumpTitleBar(tester, service);
      expect(dragArea, findsOneWidget);

      await tester.drag(dragArea, const Offset(0, -60));
      await tester.pump();

      expect(channel.methods, contains('startDragging'));

      // A press also arms the double tap on the same strip: let it lapse, so the test does not end
      // with a timer still pending.
      await tester.pump(kDoubleTapMinTime);
    });

    testWidgets('a double click on the strip toggles maximized, as it does everywhere else', (
      tester,
    ) async {
      await pumpTitleBar(tester, service);

      await tester.tap(dragArea);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(dragArea);
      await tester.pumpAndSettle();

      expect(channel.methods, contains('maximize'));
      expect(service.maximized.value, isTrue);
    });
  });

  group('buildAppWindow', () {
    testWidgets('leaves the app alone where the desktop draws the title bar', (tester) async {
      await pumpApp(tester, service, platform: TargetPlatform.android);

      expect(find.byType(WindowTitleBar), findsNothing);
      expect(find.text('the app'), findsOneWidget);
      expect(
        MediaQuery.sizeOf(tester.element(find.text('the app'))),
        const Size(800, 600),
        reason: 'the window is the app’s, whole',
      );
    });

    testWidgets('puts the strip above the app on Linux, and gives the app what is left', (
      tester,
    ) async {
      await pumpApp(tester, service, platform: TargetPlatform.linux);

      expect(find.byType(WindowTitleBar), findsOneWidget);
      expect(tester.getSize(find.byType(WindowTitleBar)).height, kWindowTitleBarHeight);

      final appSize = MediaQuery.sizeOf(tester.element(find.text('the app')));
      expect(appSize.width, 800);
      expect(appSize.height, 600 - kWindowTitleBarHeight);
    });

    testWidgets('has nothing to draw for a missing child', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [windowServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            builder: (context, child) => buildAppWindow(context, null),
            home: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byType(WindowTitleBar), findsNothing);
    });
  });
}
