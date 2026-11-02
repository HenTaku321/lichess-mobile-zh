import 'dart:convert';

import 'package:chessground/chessground.dart' show BrightnessHueFilter;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_hub_screen.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_hub_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_saved_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart';
import '../../test_provider_scope.dart';
import '../account/account_menu_test.dart' as account;
import 'xiangqi_analysis_screen_test.dart' as analysis_fixture;
import 'xiangqi_leaderboard_screen_test.dart' as leaderboard;
import 'xiangqi_online_game_screen_test.dart' as online;
import 'xiangqi_profile_screen_test.dart' as profile;
import 'xiangqi_puzzle_screen_test.dart' as puzzle;
import 'xiangqi_saved_friends_parity_test.dart' as saved;
import 'xiangqi_watch_screen_test.dart' as watch;

/// Use the actual anonymous account-preference persistence path, not a provider override.
Future<void> changeRatings(
  WidgetTester tester,
  ShowRatings preference, {
  bool liveClocks = false,
}) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  await container.read(accountPreferencesProvider.future);
  await container.read(accountPreferencesProvider.notifier).setShowRatings(preference);
  // This assertion rejects the old suite-wide `yes` override before any UI result is counted.
  expect(await container.read(showRatingsPrefProvider.future), preference);
  if (liveClocks) {
    await tester.pump();
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  TestLichessBinding.ensureInitialized();

  for (final activeGame in [false, true]) {
    for (final preference in ShowRatings.values) {
      testWidgets('shared rating rule preserves chess visibility ($activeGame, $preference)', (
        tester,
      ) async {
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            useRealRatingPreferences: true,
            home: Scaffold(
              body: RatingPrefAware(
                isActiveGameOfCurrentUser: activeGame,
                child: const Text('visible rating'),
                orElse: const Text('hidden rating'),
              ),
            ),
          ),
        );
        await changeRatings(tester, preference);
        final visible =
            preference == ShowRatings.yes ||
            (preference == ShowRatings.exceptInGame && !activeGame);
        expect(find.text('visible rating'), visible ? findsOneWidget : findsNothing);
        expect(find.text('hidden rating'), visible ? findsNothing : findsOneWidget);
      });
    }
  }

  testWidgets('a xiangqi player row reacts to the same rating preference as the chess row', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        useRealRatingPreferences: true,
        home: const Scaffold(
          body: XiangqiPlayerRow(
            side: XiangqiSide.red,
            style: XiangqiBoardStyle(),
            name: 'Rated player',
            rating: '1867',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1867'), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    expect(find.text('1867'), findsNothing);
    expect(find.text('Rated player'), findsOneWidget);
    await changeRatings(tester, ShowRatings.yes);
    expect(find.text('1867'), findsOneWidget);
  });

  testWidgets('watch rows hide ratings without hiding names or game information', (tester) async {
    await watch.pumpWatchScreen(tester, [watch.entry()], useRealRatingPreferences: true);
    expect(find.text('2815'), findsOneWidget);
    expect(find.text('2869'), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    expect(find.text('2815'), findsNothing);
    expect(find.text('2869'), findsNothing);
    expect(find.text('red-one'), findsOneWidget);
    expect(find.text('black-two'), findsOneWidget);
    await changeRatings(tester, ShowRatings.exceptInGame);
    expect(find.text('2815'), findsOneWidget, reason: 'watching is not the current user playing');
  });

  for (final playing in [true, false]) {
    testWidgets(
      'except-in-game follows the whole online game role, not just a player row ($playing)',
      (tester) async {
        final factory = await online.pumpGame(
          tester,
          useRealRatingPreferences: true,
          token: fx.xiangqiTestToken(playing ? fx.xiangqiTestViewerId : fx.xiangqiTestSpectatorId),
        );
        await online.receive(tester, factory, fx.xiangqiSnapshotFrame());
        expect(find.text('${fx.xiangqiTestBlackRating}'), findsOneWidget);
        await changeRatings(tester, ShowRatings.exceptInGame, liveClocks: true);
        expect(find.text('${fx.xiangqiTestBlackRating}'), playing ? findsNothing : findsOneWidget);
        if (playing) {
          await online.playTheGame(tester, factory);
          await online.receive(tester, factory, fx.xiangqiEndFrame());
          final finishedRating = online.playerRow(tester, XiangqiSide.black).player.rating;
          expect(finishedRating, isNotNull);
          expect(find.text('$finishedRating'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('leaderboard ratings follow the preference while rank and player remain', (
    tester,
  ) async {
    await leaderboard.pumpLeaderboard(
      tester,
      useRealRatingPreferences: true,
      boards: (_) => leaderboard.board(
        data: [leaderboard.row(name: 'Rated leader', rating: 4660)],
        totalPlayers: 1,
        totalPages: 1,
      ),
    );
    expect(find.text('4660'), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    expect(find.text('4660'), findsNothing);
    expect(find.text('Rated leader'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('Rated leader'), matching: find.byType(ListTile)),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the account subtitle hides ratings, not its online and country status', (
    tester,
  ) async {
    await account.pumpAccountMenu(
      tester,
      useRealRatingPreferences: true,
      session: account.xiangqiSession(isGuest: false),
      client: MockClient(
        (_) async => account.utf8Response(jsonEncode(account.xiangqiAccountPayload()), 200),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(account.expectedSubtitle), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    expect(find.textContaining('Puzzle 1200'), findsNothing);
    expect(find.textContaining('online'), findsWidgets);
    expect(find.textContaining('United States'), findsOneWidget);
  });

  testWidgets('profile ratings obey the preference', (tester) async {
    await profile.pumpProfile(
      tester,
      client: profile.profileClient(),
      useRealRatingPreferences: true,
    );
    expect(find.text('900'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    for (final rating in ['900', '1200', '1000', '600']) {
      expect(find.text(rating), findsNothing);
    }
    expect(find.text('a-player'), findsWidgets);
  });

  testWidgets('a profile record does not leak the highest rating when ratings are hidden', (
    tester,
  ) async {
    await profile.pumpProfile(
      tester,
      client: profile.profileClient(),
      useRealRatingPreferences: true,
    );
    await profile.scrollDown(tester);
    await profile.drain(tester);
    expect(find.textContaining('Highest rating'), findsWidgets);
    await changeRatings(tester, ShowRatings.no);
    await profile.drain(tester);
    expect(find.textContaining('Highest rating'), findsNothing);
  });

  testWidgets('saved puzzle metadata hides rating without hiding its puzzle identity', (
    tester,
  ) async {
    await saved.pumpRemote(
      tester,
      const XiangqiSavedScreen(),
      MockClient((request) async {
        if (request.url.path.startsWith('/api/puzzle/puzzles/')) {
          return saved.jsonReply({
            'items': [
              {'puzzle_id': xiangqiTestPuzzleId, 'p_rating': 1500},
            ],
            'total_pages': 1,
          });
        }
        return saved.jsonReply({'items': <Object?>[]});
      }),
      useRealRatingPreferences: true,
    );
    expect(find.textContaining('1500'), findsOneWidget);
    await changeRatings(tester, ShowRatings.no);
    expect(find.textContaining('1500'), findsNothing);
    expect(find.text(xiangqiTestPuzzleId), findsOneWidget);
  });

  testWidgets('puzzle difficulty follows the rating preference but does not hide the board', (
    tester,
  ) async {
    await puzzle.pumpPuzzleScreen(
      tester,
      server: puzzle.PuzzleServer(),
      useRealRatingPreferences: true,
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final difficulty = container
        .read(xiangqiPuzzleProvider(xiangqiTestPuzzleId))
        .requireValue
        .rating;
    expect(find.textContaining('$difficulty'), findsWidgets);
    await changeRatings(tester, ShowRatings.no);
    expect(find.textContaining('$difficulty'), findsNothing);
    expect(find.byType(XiangqiBoard), findsOneWidget);
  });

  for (final hub in [const AnalysisHubScreen(), const BoardEditorHubScreen()]) {
    testWidgets(
      '${hub.runtimeType}: both thumbnail roles disable coordinates and apply color filters',
      (tester) async {
        final prefs = BoardPrefs.defaults.copyWith(coordinates: true, brightness: 0.8, hue: 0.2);
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            home: hub,
            useRealRatingPreferences: true,
            defaultPreferences: {PrefCategory.board.storageKey: jsonEncode(prefs.toJson())},
          ),
        );
        await tester.pumpAndSettle();
        final thumbnail = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
        expect(thumbnail.showCoordinates, isFalse);
        expect(
          find.ancestor(of: find.byType(XiangqiBoard), matching: find.byType(BrightnessHueFilter)),
          findsOneWidget,
        );
        expect(thumbnail.onTapSquare, isNull);
        expect(thumbnail.onDragMove, isNull);
      },
    );
  }

  testWidgets(
    'a completed puzzle exposes analysis directly and a matching continue-training action',
    (tester) async {
      final (:engine, transport: _) = analysis_fixture.fakeXiangqiEngine();
      await puzzle.pumpPuzzleScreen(
        tester,
        server: puzzle.PuzzleServer(),
        engine: engine,
        useRealRatingPreferences: true,
        defaultPreferences: analysis_fixture.evaluationPreferences(isEnabled: false),
      );
      final l10n = tester.element(find.byType(XiangqiBoard)).l10n;
      expect(
        tester
            .widgetList<BottomBarButton>(find.byType(BottomBarButton))
            .map((button) => button.label),
        isNot(contains(l10n.analysis)),
      );
      await puzzle.playTheLine(tester);
      final completed = puzzle.attemptState(tester);
      final buttons = tester.widgetList<BottomBarButton>(find.byType(BottomBarButton)).toList();
      expect(buttons.map((button) => button.label), contains(l10n.analysis));
      expect(buttons.where((button) => button.label == l10n.getAHint), isEmpty);
      final continueTraining = buttons.singleWhere(
        (button) => button.label == l10n.puzzleContinueTraining,
      );
      expect(continueTraining.onTap, isNotNull);
      expect(continueTraining.icon, CupertinoIcons.play_arrow_solid);
      await tester.tap(find.bySemanticsLabel(l10n.analysis));
      await puzzle.settle(tester);
      expect(find.byType(XiangqiAnalysisScreen), findsOneWidget);
      final analysis = ProviderScope.containerOf(
        tester.element(
          find.descendant(
            of: find.byType(XiangqiAnalysisScreen),
            matching: find.byType(XiangqiBoard),
          ),
        ),
      ).read(xiangqiAnalysisControllerProvider);
      expect(analysis.moves, completed.moves);
      expect(analysis.positions, completed.positions);
      Navigator.of(tester.element(find.byType(XiangqiAnalysisScreen))).pop();
      await puzzle.settle(tester);
      expect(puzzle.attemptState(tester).position, completed.position);
    },
  );
}
