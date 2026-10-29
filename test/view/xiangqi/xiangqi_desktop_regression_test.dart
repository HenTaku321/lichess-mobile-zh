import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/common/chess.dart' show Variant;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/notification_service.dart';
import 'package:lichess_mobile/src/service/quick_actions.dart';
import 'package:lichess_mobile/src/service/shared_pgn_service.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_watch_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../service/fake_sound_service.dart';
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_watch_screen_test.dart' as watch;

class RecordingSound() extends FakeSoundService {
  final calls = <Sound>[];

  @override
  Future<void> play(Sound sound, {double? volume}) async => calls.add(sound);

  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) async =>
      calls.add(Sound.capture);
}

class RecordingFeedback(super.sound, super.ref) extends MoveFeedbackService {
  int moves = 0;
  int captures = 0;

  @override
  void moveFeedback({bool check = false}) {
    moves++;
    super.moveFeedback(check: check);
  }

  @override
  void captureFeedback(Variant? variant, {bool check = false}) {
    captures++;
    super.captureFeedback(variant, check: check);
  }
}

Future<({ProviderContainer container, RecordingSound sound, RecordingFeedback feedback})>
pumpAnalysis(WidgetTester tester, {bool enabled = false}) async {
  final fake = analysis.fakeXiangqiEngine();
  final sound = RecordingSound();
  late RecordingFeedback feedback;
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      surfaceSize: const Size(1280, 720),
      home: const XiangqiAnalysisScreen(),
      overrides: {
        xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((_) => fake.engine),
        soundServiceProvider: soundServiceProvider.overrideWithValue(sound),
        moveFeedbackServiceProvider: moveFeedbackServiceProvider.overrideWith(
          (ref) => feedback = RecordingFeedback(sound, ref),
        ),
      },
      defaultPreferences: analysis.evaluationPreferences(isEnabled: enabled),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiAnalysisScreen)));
  container.read(moveFeedbackServiceProvider);
  if (enabled) {
    await analysis.startSearch(tester, fake.transport);
    await analysis.answer(tester, fake.transport, 'info depth 12 score cp 40 pv h2e2');
  }
  return (container: container, sound: sound, feedback: feedback);
}

void main() {
  TestLichessBinding.ensureInitialized();
  setUp(clearSavedXiangqiAnalysis);
  tearDown(clearSavedXiangqiAnalysis);

  void testDesktop(String name, WidgetTesterCallback callback) =>
      testWidgets(name, callback, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testDesktop('desktop analysis has a menu and Lichess chip instead of a separate memory icon', (
    tester,
  ) async {
    await pumpAnalysis(tester);
    final buttons = tester.widget<BottomBar>(find.byType(BottomBar)).children;
    expect((buttons.first as BottomBarButton).icon, Icons.menu);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.restart_alt), findsNothing);
    expect(find.byIcon(Icons.memory), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter.runtimeType.toString() == 'MicroChipPainter',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Board editor'), findsOneWidget);
    expect(find.text('Clear local data'), findsOneWidget);
  });

  testDesktop('analysis display preferences independently control gauge, arrows and notation', (
    tester,
  ) async {
    final harness = await pumpAnalysis(tester, enabled: true);
    final preferences = harness.container.read(analysisPreferencesProvider.notifier);
    expect(find.byType(XiangqiEvalGauge), findsOneWidget);
    expect(analysis.board(tester).arrows, isNotEmpty);
    await preferences.toggleShowEvaluationGauge();
    await preferences.toggleShowBestMoveArrow();
    await preferences.toggleInlineNotation();
    await preferences.toggleShowEngineLines();
    await tester.pump();
    expect(find.byType(XiangqiEvalGauge), findsNothing);
    expect(analysis.board(tester).arrows, isEmpty);
    expect(tester.widget<MoveList>(find.byType(MoveList)).type, MoveListType.inline);
  });

  testDesktop('playing a shorter replacement analysis branch is still a new played move', (
    tester,
  ) async {
    final harness = await pumpAnalysis(tester);
    final controller = harness.container.read(xiangqiAnalysisControllerProvider.notifier);
    for (final move in ['h2e2', 'h9g7', 'h0g2']) {
      controller.play(XiangqiMove.parseIccs(move)!);
      await tester.pump();
    }
    controller.goTo(0);
    await tester.pump();
    final before = harness.feedback.moves;
    controller.play(XiangqiMove.parseIccs('e3e4')!);
    await tester.pump();
    expect(harness.feedback.moves, before + 1);
    expect(harness.container.read(xiangqiAnalysisControllerProvider).moves, hasLength(1));
  });

  testDesktop('returning analysis to its initial position does not invent a move sound', (
    tester,
  ) async {
    final harness = await pumpAnalysis(tester);
    final controller = harness.container.read(xiangqiAnalysisControllerProvider.notifier);
    controller.play(XiangqiMove.parseIccs('h2e2')!);
    await tester.pump();
    harness.sound.calls.clear();
    controller.goTo(0);
    await tester.pump();
    expect(harness.sound.calls, isEmpty);
  });

  testDesktop('desktop watch list has a mouse-visible refresh action', (tester) async {
    await watch.pumpWatchScreen(tester, [watch.entry()]);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testDesktop('a failed manual watch refresh retains the loaded games and stops busy state', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.path != '/api/v2/games/active') return http.Response('', 404);
      calls++;
      return calls == 1
          ? http.Response(jsonEncode([watch.entry()]), 200)
          : http.Response('unavailable', 503);
    });
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(1280, 720),
        home: const XiangqiWatchScreen(),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (_) => FakeHttpClientFactory(() => client),
          ),
        },
      ),
    );
    await watch.settle(tester);
    expect(calls, 1);
    expect(find.text('red-one'), findsOneWidget);
    expect(find.text('black-two'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await watch.settle(tester, rounds: 8);
    expect(calls, 2);
    expect(find.text('red-one'), findsOneWidget);
    expect(find.text('black-two'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testDesktop('Linux service startup does not touch mobile-only native channels or Firebase', (
    tester,
  ) async {
    await testBinding.firebaseMessaging.setAutoInitEnabled(false);
    final calls = <String>[];
    for (final name in [
      'plugins.flutter.io/quick_actions',
      'mobile.lichess.org/share',
      'mobile.lichess.org/share/events',
    ]) {
      final channel = MethodChannel(name);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('$name:${call.method}');
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
    }
    await tester.pumpWidget(
      await makeTestProviderScopeApp(tester, home: const Scaffold(body: SizedBox())),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    await container.read(notificationServiceProvider).start();
    container.read(quickActionServiceProvider).start();
    await container.read(sharedPgnServiceProvider).start();
    await tester.pump();
    expect(testBinding.firebaseMessaging.autoInitEnabled, isFalse);
    expect(calls, isEmpty);
  });
}
