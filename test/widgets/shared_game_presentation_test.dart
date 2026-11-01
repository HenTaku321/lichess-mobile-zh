import 'dart:convert';

import 'package:chessground/chessground.dart' show Chessboard;
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/opponent_level.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_controller.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_hint.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/engine/engine_gauge.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_player_row.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

const foldedSurface = Size(564.7, 482.6);
const xiangqiBoardKey = Key('xiangqi-board-surface');

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('both game shells reserve the same compact-landscape side-panel width', (
    tester,
  ) async {
    final widths = <double>[];
    for (final xiangqi in [false, true]) {
      final Widget layout = xiangqi
          ? const XiangqiGameLayout(board: SizedBox(key: xiangqiBoardKey))
          : const GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
            );
      await tester.pumpWidget(
        await makeTestProviderScope(
          tester,
          key: ValueKey(xiangqi),
          surfaceSize: foldedSurface,
          failOnOverflow: true,
          child: MaterialApp(home: layout),
        ),
      );
      final size = tester.getSize(xiangqi ? find.byKey(xiangqiBoardKey) : find.byType(Chessboard));
      widths.add(size.width);
      expect(
        size.width,
        closeTo(foldedSurface.width / kGoldenRatio - kTabletBoardTableSidePadding * 2, 0.01),
        reason: 'Compact landscape must use the same board-width budget, xiangqi=$xiangqi',
      );
      expect(size.height, closeTo(size.width * (xiangqi ? 11 / 10 : 1), 0.01));
      expect(tester.takeException(), isNull);
    }
    expect(widths.last, closeTo(widths.first, 0.01));
  });

  testWidgets('left-hand clocks align both identity lines toward the free edge', (tester) async {
    final game = OfflineComputerGameState.initial(
      opponentSpec: const StockfishOpponentSpec(StockfishLevel.level4),
      playerSide: Side.white,
    ).game;
    for (final xiangqi in [false, true]) {
      final name = xiangqi ? 'Pikafish' : 'Stockfish';
      final Widget player = xiangqi
          ? const XiangqiPlayerRow(
              side: XiangqiSide.black,
              style: XiangqiBoardStyle(),
              name: 'Pikafish',
              clock: Text('03:00'),
              clockPosition: ClockPosition.left,
            )
          : GamePlayer(
              game: game,
              side: Side.black,
              clock: const Text('03:00'),
              clockPosition: ClockPosition.left,
              shouldLinkToUserProfile: false,
            );
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(1280, 720),
          failOnOverflow: true,
          home: Center(child: SizedBox(width: 380, child: player)),
          defaultPreferences: {
            PrefCategory.board.storageKey: jsonEncode(
              BoardPrefs.defaults.copyWith(clockPosition: ClockPosition.left).toJson(),
            ),
          },
        ),
      );
      final rows = find
          .ancestor(of: find.text(name), matching: find.byType(Row))
          .evaluate()
          .map((element) => element.widget as Row);
      expect(
        rows.any((row) => row.mainAxisAlignment == MainAxisAlignment.end),
        isTrue,
        reason: 'Identity alignment must follow clock placement, xiangqi=$xiangqi',
      );
      expect(find.text('03:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('both evaluation gauges expose the translated accessibility label', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    for (final xiangqi in [false, true]) {
      final Widget gauge = xiangqi
          ? const XiangqiEvalGauge(
              redWinProbability: 0.6,
              orientation: XiangqiSide.red,
              evaluation: XiangqiEvaluation(cp: 100),
            )
          : const EngineGauge(
              params: (
                isLocalEngineAvailable: false,
                orientation: Side.white,
                position: Chess.initial,
                savedEval: null,
                serverEval: ExternalEval(cp: 100, mate: null),
                filters: (
                  context: EvaluationContext(
                    id: StringId('shared-gauge-test'),
                    variant: Variant.standard,
                    initialPosition: Chess.initial,
                  ),
                  path: null,
                ),
              ),
            );
      await tester.pumpWidget(
        await makeTestProviderScope(
          tester,
          key: ValueKey(xiangqi),
          failOnOverflow: true,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Center(child: SizedBox(width: 24, height: 300, child: gauge)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('引擎评估'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('引擎评估')).value, '+1.0');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('returning from a terminal board does not retain its checkmate label', (
    tester,
  ) async {
    final mate = Chess.fromSetup(Setup.parseFen('7k/7Q/7K/8/8/8/8/8 b - - 0 1'));
    expect(mate.outcome?.winner, Side.white);
    for (final xiangqi in [false, true]) {
      Widget gauge({bool finished = false, bool pending = false}) => xiangqi
          ? XiangqiEvalGauge(
              redWinProbability: 0.6,
              orientation: XiangqiSide.red,
              evaluation: finished || pending ? null : const XiangqiEvaluation(cp: 100),
              outcome: finished ? (winner: XiangqiSide.red) : null,
            )
          : EngineGauge(
              params: (
                isLocalEngineAvailable: false,
                orientation: Side.white,
                position: finished ? mate : Chess.initial,
                savedEval: null,
                serverEval: finished || pending ? null : const ExternalEval(cp: 100, mate: null),
                filters: (
                  context: const EvaluationContext(
                    id: StringId('terminal-gauge-test'),
                    variant: Variant.standard,
                    initialPosition: Chess.initial,
                  ),
                  path: null,
                ),
              ),
            );
      final child = ValueNotifier<Widget>(gauge());
      addTearDown(child.dispose);
      await tester.pumpWidget(
        await makeTestProviderScope(
          tester,
          key: ValueKey(xiangqi),
          failOnOverflow: true,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Center(
              child: SizedBox(
                width: 24,
                height: 300,
                child: ValueListenableBuilder(
                  valueListenable: child,
                  builder: (_, value, _) => value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('+1.0'), findsOneWidget);
      child.value = gauge(finished: true);
      await tester.pump();
      expect(find.text('#'), findsOneWidget);
      child.value = gauge(pending: true);
      await tester.pump();
      expect(
        find.text('#'),
        findsNothing,
        reason: 'A historical position is not mate, xiangqi=$xiangqi',
      );
      expect(find.text('+1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
