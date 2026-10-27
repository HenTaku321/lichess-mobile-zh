import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/home/games_carousel.dart'
    show kGameCarouselFlexWeights, kGameCarouselPadding;
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// A xiangqi ongoing game, as a row of the merged ongoing-games list.
///
/// The xiangqi counterpart of `OngoingGamePreview`: it is built to the same
/// measurements so that a xiangqi row and a chess row sitting one above the
/// other on the same screen read as two rows of one list rather than two apps.
/// The board box is sized by the same formula, the description column is the same
/// column, and the only things that differ are the ones that have to — a xiangqi
/// board instead of a chess board, and the time control instead of a perf icon,
/// because a xiangqi game has no perf.
///
/// The clock line follows the chess row exactly: while it is this user's turn and
/// their clock is running it counts down, and otherwise it says whose move it is.
class const XiangqiOngoingGamePreview({
  required final XiangqiOpenGame game,
  final EdgeInsetsGeometry? padding,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);

    final content = LayoutBuilder(
      builder: (context, constraints) {
        // The chess list row's own sizing formula, kept identical so the two kinds
        // of row are the same height: the board takes all but a 1.518nd of the
        // shorter side, the rest being the description beside it.
        final boardSize =
            constraints.biggest.shortestSide - (constraints.biggest.shortestSide / 1.518);
        return Padding(
          padding:
              padding ??
              Styles.horizontalBodyPadding.add(const EdgeInsets.symmetric(vertical: 8.0)),
          child: SizedBox(
            height: boardSize,
            child: Row(
              children: [
                SizedBox(
                  width: boardSize * (boardPrefs.coordinates ? 10 / 11 : 0.9),
                  height: boardSize,
                  child: ClipRRect(
                    // The same corner treatment the chess preview gives its board.
                    borderRadius: Styles.boardBorderRadius,
                    child: BrightnessHueFilter(
                      brightness: boardPrefs.brightness,
                      hue: boardPrefs.hue,
                      child: XiangqiBoard(
                        settings: XiangqiBoardSettings.fromPreferences(
                          boardPrefs,
                          annotations: false,
                        ),
                        position: XiangqiPosition.fromFen(game.fen),
                        orientation: game.mySide,
                        showCoordinates: boardPrefs.coordinates,
                        showBorder: boardPrefs.showBorder,
                        style: XiangqiBoardStyle.fromChessboardColorScheme(
                          boardPrefs.boardTheme.colors,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      UserFullNameWidget.player(
                        user: game.opponent,
                        rating: game.opponentRating,
                        // A xiangqi opponent off this list is a person on
                        // xiangqi.com; there is no engine seat to name.
                        aiLevel: null,
                        style: Styles.boardPreviewTitle,
                      ),
                      // Where the chess row shows the perf icon, a xiangqi row
                      // shows the time control: a xiangqi game has no perf, and
                      // this is the one label the row has about the game itself.
                      // Like the icon it takes the turn colour, so a row that
                      // wants a move stands out from one that is waiting.
                      Text(
                        xiangqiTimeControl(game),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: game.isMyTurn
                              ? context.lichessColors.brag
                              : DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.5),
                        ),
                      ),
                      Text(_turnLabel(context, game)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return InkWell(
      onTap: () {
        Navigator.of(
          context,
          rootNavigator: true,
        ).push(XiangqiOnlineGameScreen.buildRoute(game.id));
      },
      child: content,
    );
  }

  /// The line under the time control: whose move it is, or how long this user has
  /// left when it is theirs and the clock is running.
  String _turnLabel(BuildContext context, XiangqiOpenGame game) {
    if (!game.isMyTurn) return context.l10n.waitingForOpponent;
    final secondsLeft = game.mySide == XiangqiSide.red
        ? game.redSecondsLeft
        : game.blackSecondsLeft;
    if (secondsLeft == null) return context.l10n.yourTurn;
    return relativeDate(context.l10n, DateTime.now().add(Duration(seconds: secondsLeft)));
  }
}

/// A xiangqi ongoing game, as a card of the home carousel.
///
/// The xiangqi counterpart of `OngoingGameCarouselItem`, built to that card's
/// layout — the same board box, the same green real-time wash behind it, the same
/// description over the board's bottom edge — so that a xiangqi card and a chess
/// card swiped past one another look like two cards of one carousel.
///
/// Every game on this card is a live one (see [XiangqiOngoingGame.isRealTime]), so
/// it always wears the real-time colouring rather than the correspondence one.
class const XiangqiOngoingGameCarouselItem({required final XiangqiOpenGame game})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeControl = xiangqiTimeControl(game);
    final timeTextStyle = TextStyle(
      color: Colors.white.withValues(alpha: game.isMyTurn ? 1.0 : 0.7),
      fontSize: TextTheme.of(context).labelMedium?.fontSize,
      fontWeight: FontWeight.w500,
    );

    return Opacity(
      // The chess card's own opacity. It reads `isRealTime || isMyTurn`, and a
      // xiangqi game is always real-time, so the condition is always true.
      opacity: 0.9,
      child: _XiangqiBoardCarouselItem(
        position: XiangqiPosition.fromFen(game.fen),
        orientation: game.mySide,
        description: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Same shape as the chess card: a timer beside the label while
                    // it is this user's turn, and the "waiting" sentence otherwise.
                    // The label is the time control rather than a countdown because
                    // that is the one clock label a xiangqi game carries.
                    if (game.isMyTurn) ...[
                      const Icon(Icons.timer, size: 16.0, color: Colors.white),
                      const SizedBox(width: 4.0),
                      Text(timeControl, style: timeTextStyle),
                    ] else
                      Text(context.l10n.waitingForOpponent, style: timeTextStyle),
                  ],
                ),
                const SizedBox(height: 4.0),
                UserFullNameWidget.player(
                  user: game.opponent,
                  rating: game.opponentRating,
                  aiLevel: null,
                  style: Styles.boardPreviewTitle.copyWith(
                    color: Colors.white.withValues(alpha: game.isMyTurn ? 1.0 : 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The board-and-description box of a xiangqi carousel card, the counterpart of
/// the chess card's own `_BoardCarouselItem`.
///
/// One board over one coloured background, the description laid over the board's
/// bottom edge. The box's size is measured exactly as the chess card measures its
/// own — the same carousel flex weights and padding — so a card fills its cell the
/// same way whatever game is on it.
///
/// The colour is the real-time one: the card is always live, so it always paints
/// the green the chess carousel reserves for a running game, and the board is
/// dressed in that same green through [XiangqiBoardStyle.fromChessboardColorScheme],
/// so the two agree.
class const _XiangqiBoardCarouselItem({
  required final XiangqiPosition position,
  required final XiangqiSide orientation,
  required final Widget description,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final brightness = ColorScheme.of(context).brightness;

    // The chess card's real-time wash, applied to the brag colour, and then the
    // same hue rotation the board preferences apply everywhere else.
    final backgroundColor = lighten(
      context.lichessColors.brag,
      brightness == Brightness.light ? 0.25 : 0.0,
    );
    final hsl = HSLColor.fromColor(backgroundColor);
    final hue = (hsl.hue + boardPrefs.hue) % 360;
    final backgroundColorWithHueFilter = HSLColor.fromAHSL(
      1.0,
      hue,
      hsl.saturation,
      hsl.lightness,
    ).toColor();

    final screenWidth = MediaQuery.widthOf(context);
    final totalFlex = kGameCarouselFlexWeights.reduce((a, b) => a + b);
    final double width = screenWidth - 16.0;
    final boardSize =
        width * kGameCarouselFlexWeights[0] / totalFlex - kGameCarouselPadding.horizontal;

    return ColoredBox(
      color: backgroundColorWithHueFilter,
      child: OverflowBox(
        maxWidth: boardSize,
        minWidth: boardSize,
        child: Stack(
          children: [
            SizedBox(
              height: boardSize,
              width: boardSize,
              child: ClipRRect(
                // The chess card rounds only the board's top corners, the card's
                // own bottom corners being the carousel's.
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10.0),
                  topRight: Radius.circular(10.0),
                ),
                child: BrightnessHueFilter(
                  brightness: boardPrefs.brightness,
                  hue: boardPrefs.hue,
                  child: XiangqiBoard(
                    settings: XiangqiBoardSettings.fromPreferences(boardPrefs, annotations: false),
                    position: position,
                    orientation: orientation,
                    showCoordinates: boardPrefs.coordinates,
                    showBorder: boardPrefs.showBorder,
                    style: XiangqiBoardStyle.fromChessboardColorScheme(
                      _realTimeColorScheme(context),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 8,
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: description,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The chessboard colours a real-time card is painted in.
  ///
  /// The chess card builds these itself from its `brag` colour (see
  /// `_BoardCarouselItem.realTimeColors`); a xiangqi board cannot wear a
  /// [ChessboardColorScheme] directly, but [XiangqiBoardStyle.fromChessboardColorScheme]
  /// reads the two flat colours and the move highlights out of one, so the same
  /// scheme gives the xiangqi board the same green a chess real-time card has.
  ChessboardColorScheme _realTimeColorScheme(BuildContext context) {
    final brag = context.lichessColors.brag;
    final lightSquare = lighten(brag, 0.55);
    final darkSquare = brag;
    return ChessboardColorScheme(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      background: SolidColorChessboardBackground(lightSquare: lightSquare, darkSquare: darkSquare),
      whiteCoordBackground: SolidColorChessboardBackground(
        lightSquare: lightSquare,
        darkSquare: darkSquare,
        coordinates: true,
      ),
      blackCoordBackground: SolidColorChessboardBackground(
        lightSquare: lightSquare,
        darkSquare: darkSquare,
        coordinates: true,
        orientation: Side.black,
      ),
      lastMove: const HighlightDetails(solidColor: Color(0x809cc700)),
      selected: const HighlightDetails(solidColor: Color(0x6014551e)),
      validMoves: const Color(0x4014551e),
      validPremoves: const Color(0x40203085),
    );
  }
}

/// A xiangqi game's time control, written the way a player reads one: `10+0`,
/// `5+3`, `1:30+0`.
///
/// The two numbers are the whole of it — `gameTimeSeconds` a side starts with, and
/// `incrementSeconds` added on each move — so this only has to spell them. A
/// whole number of minutes is written bare (the usual `5+3`), and a part-minute
/// keeps its seconds so that a `1:30` game is not rounded into a `2+0` one.
String xiangqiTimeControl(XiangqiOpenGame game) {
  final seconds = game.gameTimeSeconds;
  final base = seconds % 60 == 0
      ? '${seconds ~/ 60}'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  return '$base+${game.incrementSeconds}';
}
