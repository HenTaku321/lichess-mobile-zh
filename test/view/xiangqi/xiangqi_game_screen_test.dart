import 'dart:convert';

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/non_linear_slider.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_game_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The square named [name], which the tests below write the way a player would.
XiangqiSquare squareAt(String name) {
  final square = XiangqiSquare.parse(name);
  if (square == null) throw ArgumentError('Not a square: $name');
  return square;
}

/// The move written [iccs], which is also how Pikafish writes one.
XiangqiMove moveAt(String iccs) {
  final move = XiangqiMove.parseIccs(iccs);
  if (move == null) throw ArgumentError('Not a move: $iccs');
  return move;
}

/// The new game sheet's own side setting: the tile that says which side the player takes.
///
/// Scoped to the tile rather than looked for by its text alone, because the board's player row
/// prints the side's name too — `Red` is the value in this tile and also the name printed under the
/// board's own red general — so a bare `find.text('Red')` would find both and a tap on it would be
/// ambiguous.
Finder sideSettingTile() =>
    find.ancestor(of: find.text('Side'), matching: find.byType(SettingsListTile));

/// The app the screen is pumped into when a test asks for a language of its own.
///
/// The shared test harness puts the screen into its own [MaterialApp], which declares no languages
/// and so takes Flutter's default of `[en_US]`: whatever the platform reports, a test runs in
/// English, which is why every expectation in this file is written in English. Production declares
/// every language the app has, and passes the one the player chose (see `app.dart`); this is that,
/// with [locale] standing in for the choice.
Widget appInLocale(Locale locale, Widget home) => MaterialApp(
  // Not [AppLocalizations.localizationsDelegates]: the generated list is built on the
  // `flutter_localizations` delegates, which localize Flutter's own material and cupertino
  // libraries rather than the `material_ui` and `cupertino_ui` ones the app is built with.
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
    MaterialLocalizationsEo.delegate,
    CupertinoLocalizationsEo.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: home,
);

/// Pumps the game screen with an engine whose transport is fake, and hands that transport back.
///
/// The game's own engine provider is replaced rather than the factory behind it, exactly as the
/// controller's tests do it: an [Engine] over a [FakeTransport] is the smallest thing that answers
/// the way Pikafish does, so the handshake, the option hygiene, the commands and the `bestmove`
/// parsing are all the real ones and only the bytes in and out are not. It is also what the game
/// needs to be testable at all — the engine it really starts is a 48 MB network written out of the
/// bundle first, which a test surface has nowhere to put.
///
/// The evaluation is off unless [engineEvaluation] asks for it. The engine is one engine and the
/// screen shares it between the opponent and the evaluation bar, so an evaluation left running would
/// take the engine out from under the opponent's search and the commands the tests read — the
/// `go` an answer is made of — would belong to the bar instead.
///
/// [locale] is the language to run in, and the one test that is about the language the app is
/// running in passes it; everything else leaves it null and gets the harness's app.
///
/// [initialFen] is the position to open the screen on, and only the test about opening on one passes
/// it: a screen given a position is a screen on a game that has not started yet, and its own behaviour
/// is what that test is about.
Future<FakeTransport> pumpGameScreen(
  WidgetTester tester, {
  Size surfaceSize = kTestSurfaceSize,
  bool engineEvaluation = false,
  Locale? locale,
  String? initialFen,
}) async {
  final transport = FakeTransport(
    spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
    startupLines: kPikafishHandshake,
  );
  final engine = Engine(transport);
  addTearDown(engine.dispose);

  final home = XiangqiGameScreen(initialFen: initialFen);
  final overrides = {
    xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine),
  };
  final defaultPreferences = {
    PrefCategory.engineEvaluation.storageKey: jsonEncode(
      EngineEvaluationPrefState.defaults.copyWith(isEnabled: engineEvaluation).toJson(),
    ),
  };

  await tester.pumpWidget(
    locale == null
        ? await makeTestProviderScopeApp(
            tester,
            home: home,
            overrides: overrides,
            defaultPreferences: defaultPreferences,
            surfaceSize: surfaceSize,
          )
        : await makeTestProviderScope(
            tester,
            child: appInLocale(locale, home),
            overrides: overrides,
            defaultPreferences: defaultPreferences,
            surfaceSize: surfaceSize,
          ),
  );
  await tester.pumpAndSettle();
  return transport;
}

/// Answers the `isready` the engine is waiting on, which is what lets it start searching.
///
/// Pumped rather than awaited on a real clock: a widget test's body runs in fake time, so anything
/// that waits on a timer would wait for a clock nothing is advancing. Two pumps per line, because
/// they do different things — the first delivers the line and flushes the microtasks it sets off,
/// and the second draws what those microtasks changed. One pump is not enough: the frame that would
/// carry the change is only scheduled as the first one ends, so a single pump leaves the tree
/// showing the state before it.
Future<void> startSearch(WidgetTester tester, FakeTransport transport) async {
  await tester.pump();
  transport.emit('readyok');
  await tester.pump();
  await tester.pump();
}

/// Lets the engine reach its `bestmove`, as a real one does once it is asked to search.
Future<void> answer(WidgetTester tester, FakeTransport transport, String iccs) async {
  await startSearch(tester, transport);
  transport.emit('bestmove $iccs');
  await tester.pump();
  await tester.pump();
}

/// Touches the point [name] names, in the orientation these tests play from: red at the bottom.
///
/// Aimed at the drawn board rather than at the box it is drawn in, which are not the same thing: the
/// board takes the largest board that fits its room and centres it, so on a phone-shaped surface —
/// taller than the board's own 10:11 — there is a band of the box above and below the board, and a
/// touch aimed at the box's top-left corner would land beside it.
///
/// The geometry is measured with the coordinates on, which is the preference's default: they widen
/// the board's margin by half a cell on every side, and a geometry measured without them would put
/// every square half a cell off from where the board drew it.
Future<void> tapSquare(WidgetTester tester, String name) async {
  final box = tester.getRect(find.byType(XiangqiBoard));
  final geometry = XiangqiBoardGeometry.fit(box.size, showCoordinates: true);
  final board = Rect.fromCenter(center: box.center, width: geometry.width, height: geometry.height);
  await tester.tapAt(board.topLeft + geometry.centerOf(squareAt(name), .red));
  await tester.pump();
}

/// The bar button under [icon], which is how the buttons are found: their labels are tooltips and
/// semantics, not text on screen, and their `onTap` is what says whether they are live.
BottomBarButton barButton(WidgetTester tester, IconData icon) => tester.widget<BottomBarButton>(
  find.ancestor(of: find.byIcon(icon), matching: find.byType(BottomBarButton)),
);

/// The container the screen is running in, for reading the game's state straight off the tree.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(XiangqiGameScreen)));

/// A well formed position that is not the opening: the standard arrangement, black to move.
const String kBlackToMoveFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1';

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiGameScreen', () {
    testWidgets('opens on a game the player can start at once', (tester) async {
      await pumpGameScreen(tester);

      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(find.text('Your turn'), findsOneWidget);

      // Red is the side that moves first, so the game is the player's and nothing is asked of the
      // engine until they have moved — which is what a takeback with nothing to take back means.
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNotNull);
      // A hint is the player asking the engine a question, and the engine is free until the
      // opponent needs it: the button is live exactly while the computer is not thinking.
      expect(barButton(tester, CupertinoIcons.lightbulb).onTap, isNotNull);
      expect(find.text('Computer thinking ...'), findsNothing);
    });

    testWidgets('the evaluation bar is drawn beside the board when the evaluation is on', (
      tester,
    ) async {
      await pumpGameScreen(tester, engineEvaluation: true);

      // A search of the opening position has been started, and until it has said anything the bar
      // is drawn level rather than left out: a bar that came and went on every move would flicker.
      final gauge = tester.widget<XiangqiEvalGauge>(find.byType(XiangqiEvalGauge));
      expect(gauge.redWinProbability, 0.5);
      expect(gauge.evaluation, isNull);
      // The board is drawn from red's side here, so the bar is too: red's end of it is the bottom.
      expect(gauge.orientation, XiangqiSide.red);
    });

    testWidgets('a hint is drawn as an arrow from the piece to its destination', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.lightbulb));
      await tester.pump();
      await startSearch(tester, transport);
      transport.emit('info depth 9 score cp 34 nodes 9450 time 90 pv h2e2');
      await tester.pump();
      transport.emit('bestmove h2e2');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.hint, moveAt('h2e2'));
      expect(board.arrows.single.move, moveAt('h2e2'));
    });

    testWidgets('there is no evaluation bar when the evaluation is off', (tester) async {
      await pumpGameScreen(tester);

      expect(find.byType(XiangqiEvalGauge), findsNothing);
    });

    testWidgets('the player moves and the computer answers', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tapSquare(tester, 'h2');
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).selected, squareAt('h2'));

      await tapSquare(tester, 'e2');
      expect(find.text('Computer thinking ...'), findsOneWidget);
      // The engine is one engine, and while the computer is thinking it is the computer's: a hint
      // asked for now would take it out from under the search the opponent's move is coming from.
      expect(barButton(tester, CupertinoIcons.lightbulb).onTap, isNull);

      await answer(tester, transport, 'h9g7');

      expect(find.text('Your turn'), findsOneWidget);
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).lastMove, moveAt('h9g7'));
      // Both sides have moved, so there is something for the player to take back, and the engine is
      // the player's again.
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNotNull);
      expect(barButton(tester, CupertinoIcons.lightbulb).onTap, isNotNull);
    });

    testWidgets('picking a piece up and putting it down again is all it takes to move', (
      tester,
    ) async {
      await pumpGameScreen(tester);

      // A touch on the player's own piece picks it up and shows where it may go; a touch on a
      // square that is not one of those puts it back down.
      await tapSquare(tester, 'h2');
      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.selected, squareAt('h2'));
      expect(board.moves, contains(moveAt('h2e2')));

      await tapSquare(tester, 'a9');
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).selected, isNull);
    });

    testWidgets('taking a move back hands the turn to the player again', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await answer(tester, transport, 'h9g7');
      expect(find.text('Your turn'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.arrow_uturn_left));
      await tester.pump();

      // The player's move and the answer to it both come off, so the game is theirs to play again.
      expect(find.text('Your turn'), findsOneWidget);
      final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
      expect(board.lastMove, isNull);
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);
    });

    testWidgets('resigning asks first, and then says how the game ended', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.flag));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      // The result comes half a second after the game ends, so that the move which ended it is on
      // the board and read before the dialog comes down over it.
      await tester.pump();
      expect(find.byType(XiangqiGameResultDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Game Over'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(XiangqiGameResultDialog),
          matching: find.text('Red resigned.'),
        ),
        findsOneWidget,
      );
      // A game that is over is a game with nothing left to do to it.
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNull);
      expect(barButton(tester, CupertinoIcons.arrow_uturn_left).onTap, isNull);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(XiangqiGameResultDialog), findsNothing);
      // What the game ended as stays on the line under the board.
      expect(find.text('Red resigned.'), findsOneWidget);
    });

    testWidgets('saying no to resigning leaves the game alone', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.flag));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.text('Your turn'), findsOneWidget);
      expect(barButton(tester, CupertinoIcons.flag).onTap, isNotNull);
    });

    testWidgets('names both seats: the engine with its badge, the player with their side', (
      tester,
    ) async {
      await pumpGameScreen(tester);

      // The engine's own name, and the badge that says the seat is a program rather than a person —
      // the same badge the chess screens put on an engine's row.
      expect(find.text('Pikafish'), findsOneWidget);
      expect(find.text('Computer'), findsOneWidget);

      // Nobody is signed in here, so the player's row falls back to the side they are playing,
      // which is how the online row names a seat nobody has taken yet. The row's own name is the
      // only one on the screen: the sheet that also prints a side is not open.
      expect(find.text('Red'), findsOneWidget);
      expect(find.text('Your turn'), findsOneWidget);
    });

    testWidgets('the new game sheet opens on the game in progress', (tester) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();

      expect(find.text('Side'), findsOneWidget);
      expect(find.descendant(of: sideSettingTile(), matching: find.text('Red')), findsOneWidget);
      // The computer is the whole of the opponent here, so the control for it is the app's own level
      // control for one, and its title is the app's own word for a level rather than a word of this
      // screen's inventing: a level is a search budget, and there are no words that could say which
      // of two budgets is the stronger. See [_XiangqiLevelTile].
      expect(find.text('Level: ${XiangqiDifficulty.defaultLevel.level}'), findsOneWidget);
    });

    testWidgets('taking black hands the opening move to the computer, and says so', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: sideSettingTile(), matching: find.text('Red')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black').last);
      await tester.pumpAndSettle();
      // 让先 is not a setting of its own — red moves first, so taking black is handing the opening
      // move over — and the sheet says so at the moment the choice is made.
      expect(find.text('Red moves first, so the computer opens the game.'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.text('Computer thinking ...'), findsOneWidget);
      await answer(tester, transport, 'h2e2');
      expect(find.text('Your turn'), findsOneWidget);

      // The board is drawn the other way up, so the engine's move is the one nearest the player.
      expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).orientation, XiangqiSide.black);
    });

    testWidgets('choosing a difficulty starts a game at that difficulty', (tester) async {
      final transport = await pumpGameScreen(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();
      expect(find.text('Level: ${XiangqiDifficulty.defaultLevel.level}'), findsOneWidget);

      // The control is a slider over the levels, so it is moved the way the widget itself moves it:
      // what it hands back is the level's number, not the slider's own index.
      tester.widget<NonLinearSlider>(find.byType(NonLinearSlider)).onChangeEnd!(1);
      await tester.pumpAndSettle();
      expect(find.text('Level: 1'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await tapSquare(tester, 'h2');
      await tapSquare(tester, 'e2');
      await startSearch(tester, transport);

      // What the difficulty is, is how much the computer is allowed to think: six levels, six search
      // budgets, because Pikafish has no strength setting to set. See [XiangqiDifficulty].
      expect(transport.takeCommands(), contains('go movetime 1 depth 1'));
    });

    testWidgets('says how the game ended in the language the app is running in', (tester) async {
      // The sentences are the app's own translations and the side they name is translated with
      // them — see [XiangqiSide.label] — so a reader of the Chinese app reads the whole of it in
      // Chinese, the side named inside it included.
      await pumpGameScreen(tester, locale: const Locale('zh'));

      await tester.tap(find.byIcon(CupertinoIcons.flag));
      await tester.pumpAndSettle();
      await tester.tap(find.text('是'));
      // The result comes half a second after the game ends, as it does in the English tests.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(XiangqiGameResultDialog), matching: find.text('红方认输。')),
        findsOneWidget,
      );

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      // And what the game ended as stays on the line under the board.
      expect(find.text('红方认输。'), findsOneWidget);
    });

    testWidgets('the settings sheet offers the drag settings and the blindfold switch', (
      tester,
    ) async {
      await pumpGameScreen(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // The board the screen is building behind the sheet, which is what these settings are for.
      XiangqiBoard board() => tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));

      // The line under the difficulty setting, which is this game's own: what a level controls is
      // how long the engine may think, and that is not true of the chess opponent beside it.
      expect(find.text('How long the computer is allowed to think.'), findsOneWidget);

      // Magnified or plain under the finger.
      final magnifySwitch = find.descendant(
        of: find.ancestor(
          of: find.text('Magnify dragged piece'),
          matching: find.byType(SwitchSettingTile),
        ),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(find.text('Magnify dragged piece'));
      await tester.tap(magnifySwitch);
      await tester.pumpAndSettle();
      expect(board().magnifyDraggedPiece, isFalse);

      // The shape drawn on the square a dragged piece is over.
      await tester.ensureVisible(find.text('Target of dragged piece'));
      await tester.tap(find.text('Target of dragged piece'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square').last);
      await tester.pumpAndSettle();
      expect(board().dragTargetKind, DragTargetKind.square);

      // The two board appearance switches are wired to this board, not only to the chess one.
      final coordinatesSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('Board coordinates (A-I, 0-9)'),
          matching: find.byType(SwitchSettingTile),
        ),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(find.text('Board coordinates (A-I, 0-9)'));
      await tester.tap(coordinatesSwitch);
      await tester.pumpAndSettle();
      expect(board().showCoordinates, isFalse);

      final borderSwitch = find.descendant(
        of: find.ancestor(of: find.text('Show border'), matching: find.byType(SwitchSettingTile)),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(find.text('Show border'));
      await tester.tap(borderSwitch);
      await tester.pumpAndSettle();
      expect(board().showBorder, isTrue);

      // Blindfold, which is the same preference the chess game against the computer keeps: the same
      // kind of game, with the pieces taken off the board.
      final blindfoldSwitch = find.descendant(
        of: find.ancestor(of: find.text('Blindfold'), matching: find.byType(SwitchSettingTile)),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(find.text('Blindfold'));
      await tester.tap(blindfoldSwitch);
      await tester.pumpAndSettle();
      expect(board().blindfoldMode, isTrue);
    });

    testWidgets('a screen opened on a position offers to set a game up on it', (tester) async {
      final start = XiangqiPosition.fromFen(kBlackToMoveFen);
      await pumpGameScreen(tester, initialFen: start.toFen());

      // The sheet comes up by itself: a position handed to the screen is a game to be set up on it,
      // not a game in progress to be resumed, and the screen does not go looking for a session.
      expect(find.text('Side'), findsOneWidget);

      // The sheet draws the position above the controls, so what is being set up is read rather than
      // imagined. Read only: a preview has no callbacks, which is also what tells it apart from the
      // board behind the sheet.
      final preview = tester
          .widgetList<XiangqiBoard>(find.byType(XiangqiBoard))
          .firstWhere((board) => board.onTapSquare == null);
      expect(preview.position.toFen(), start.toFen());
      expect(preview.onDragMove, isNull, reason: 'a preview is not a board to move pieces on');
      // Nine files by ten ranks with the coordinates on (the preference's default), the same ratio
      // the layout sizes the board by — see [XiangqiGameLayout].
      expect(
        tester.getSize(find.byWidget(preview)).aspectRatio,
        closeTo(10 / 11, 0.001),
        reason: 'the preview is the board at its own shape, not whatever room it is given',
      );

      // The player takes the side the position says is to move — black here, meant to move first —
      // rather than the game screen's own default of red.
      expect(find.text('Black'), findsOneWidget);
      expect(find.text('Red moves first, so the computer opens the game.'), findsOneWidget);

      // The preview makes the sheet taller than the room it is given, so the button at the bottom of
      // it has to be scrolled to before it can be pressed — the same the settings sheet's own tiles
      // are.
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final state = containerOf(tester).read(xiangqiGameControllerProvider);
      expect(state.position.toFen(), start.toFen());
      expect(state.moves, isEmpty, reason: 'a game from a position begins on it');
      expect(state.playerSide, XiangqiSide.black);
    });
  });
}
