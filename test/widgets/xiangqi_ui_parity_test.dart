import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refreshable_empty.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';
import 'xiangqi_board_test.dart' show painterOf, pumpBoard;

void main() {
  testWidgets('compact analysis seats fit the 26px header without a second name row', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const Center(
          child: SizedBox(
            width: 320,
            height: 26,
            child: XiangqiPlayerRow(
              compact: true,
              avatarSize: 24,
              side: .red,
              style: XiangqiBoardStyle(),
              name: 'A very long analysis player name',
              rating: '2500',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('A very long analysis player name')).style!.fontSize, 13);
  });
  test('board settings mirror the existing shared preferences', () {
    final prefs = BoardPrefs.defaults.copyWith(
      pieceShiftMethod: .tapTwoSquares,
      moveOnRelease: true,
      boardHighlights: false,
      enableShapeDrawings: false,
      shapeColor: .red,
    );
    final settings = XiangqiBoardSettings.fromPreferences(prefs);
    expect(settings.pieceShiftMethod, prefs.pieceShiftMethod);
    expect(settings.moveOnRelease, prefs.moveOnRelease);
    expect(settings.boardHighlights, prefs.boardHighlights);
    expect(settings.enableShapeDrawings, prefs.enableShapeDrawings);
    expect(settings.shapeColor, prefs.shapeColor.color);
  });

  testWidgets('disabling highlights hides check without changing the board position', (
    tester,
  ) async {
    final position = XiangqiPosition.fromFen('4k4/9/9/9/4r4/9/9/9/9/4K4 w - - 0 1');
    await pumpBoard(
      tester,
      XiangqiBoard(
        position: position,
        settings: const XiangqiBoardSettings(boardHighlights: false),
      ),
    );
    expect(painterOf(tester).isCheck, isFalse);
    expect(painterOf(tester).position, position);
  });

  for (final size in const [
    Size(320, 568),
    Size(375, 812),
    Size(768, 1024),
    Size(812, 375),
    Size(1100, 700),
  ]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('layout remains bounded at $size, text scale $scale, with gauge', (tester) async {
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            surfaceSize: size,
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
              child: const XiangqiGameLayout(
                board: SizedBox(key: Key('parity-board')),
                topTable: Text('Opponent'),
                bottomTable: Text('Player'),
                moves: IListConst(['炮二平五']),
                evalGauge: XiangqiEvalGauge(redWinProbability: 0.5, orientation: .red),
              ),
            ),
          ),
        );
        await tester.pump();
        final rect = tester.getRect(find.byKey(const Key('parity-board')));
        expect(rect.width, greaterThanOrEqualTo(0));
        expect(rect.height, greaterThanOrEqualTo(0));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 801));
      });
    }
  }

  testWidgets('evaluation uses the Lichess tween and preserves negative mate signs', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const SizedBox(
          width: 24,
          height: 200,
          child: XiangqiEvalGauge(
            redWinProbability: 0.1,
            orientation: .red,
            evaluation: XiangqiEvaluation(mate: -3),
          ),
        ),
      ),
    );
    expect(find.text('#-3'), findsOneWidget);
    final tween = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(tween.duration, const Duration(milliseconds: 800));
    expect(tween.curve, Curves.ease);
    await tester.pump(const Duration(milliseconds: 801));
  });

  for (final position in ClockPosition.values) {
    testWidgets('player rows put a constrained clock on $position', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: Center(
            child: SizedBox(
              width: 320,
              child: XiangqiPlayerRow(
                side: .red,
                style: const XiangqiBoardStyle(),
                name: 'A very long player name that must ellipsize',
                rating: '2500',
                clockPosition: position,
                clock: const Clock(timeLeft: Duration(seconds: 20)),
              ),
            ),
          ),
        ),
      );
      final clock = tester.getRect(find.byType(Clock));
      final name = tester.getRect(find.text('A very long player name that must ellipsize'));
      expect(position == .left ? clock.right <= name.left : clock.left >= name.right, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty remote list remains scrollable for refresh', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: XiangqiRefreshableEmpty(onRefresh: () async {}, child: const Text('No games')),
      ),
    );
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    expect(find.text('No games'), findsOneWidget);
  });
}
