import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refreshable_empty.dart';
import 'package:material_ui/material_ui.dart';

/// The games being played on xiangqi.com right now, and the way into watching one.
///
/// ## What this screen is, and what it is not
///
/// It is a list of twenty games between other people, drawn from `GET /api/v2/games/active`. It is
/// not a list of *your* games — those are on the home screen's ongoing-games list, and they are a
/// different question — and it is not lichess TV: there is no featured channel, no curated game and
/// no commentary, because xiangqi.com has none of those. What it has is whoever happens to be
/// playing, in the order the server lists them.
///
/// ## What a row can and cannot say
///
/// A row is two names, two ratings, two clocks, a time control and a move count, and that is the
/// whole of what the endpoint carries. **It carries no position**, so no row draws a board: a board
/// would have to be the starting position, which is a board that is not the game. The position is
/// only in the socket's own snapshot, and that is what the screen behind a row asks for.
///
/// Which side is to move is read from the move count rather than from a field, for the same reason
/// — see [XiangqiLiveGame.turn] — and it is what shades the seat that is thinking.
class const XiangqiWatchScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiWatchScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return XiangqiRefreshScope(
      onRefresh: () => ref.refresh(xiangqiLiveGamesProvider.future),
      builder: (context, refresh, busy) => Scaffold(
        appBar: AppBar(
          title: AppBarTitleText(
            '${context.l10n.mobileXiangqi} · ${context.l10n.mobileWatchGames}',
          ),
          actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
        ),
        body: _Body(onRefresh: refresh),
      ),
    );
  }
}

class const _Body({required final Future<void> Function() onRefresh}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(xiangqiLiveGamesProvider);

    return games.when(
      skipError: true,
      data: (games) => games.isEmpty
          ? XiangqiRefreshableEmpty(
              onRefresh: onRefresh,
              child: const Padding(padding: Styles.bodySectionPadding, child: _NoGames()),
            )
          : RefreshIndicator.adaptive(
              onRefresh: onRefresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: games.length,
                itemBuilder: (context, index) => _LiveGameTile(game: games[index]),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: Styles.bodySectionPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
              const SizedBox(height: 16.0),
              FilledButton(onPressed: onRefresh, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One game being played, and the way into watching it.
///
/// The two seats are stacked the way they are on the board — red above black, which is the order
/// the notation and every diagram of a xiangqi game is written in — and the footer line is what the
/// two of them are playing: the time control, how far along the game is, and whether it counts.
class const _LiveGameTile({required final XiangqiLiveGame game}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = XiangqiBoardStyle.fromChessboardColorScheme(
      ref.watch(boardPreferencesProvider).boardTheme.colors,
    );

    return InkWell(
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiOnlineGameScreen.buildRoute(game.id)),
      child: Padding(
        padding: Styles.horizontalBodyPadding.add(const EdgeInsets.symmetric(vertical: 10.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeatLine(
              side: XiangqiSide.red,
              player: game.red,
              isTurn: game.turn == XiangqiSide.red,
              style: style,
            ),
            const SizedBox(height: 6.0),
            _SeatLine(
              side: XiangqiSide.black,
              player: game.black,
              isTurn: game.turn == XiangqiSide.black,
              style: style,
            ),
            const SizedBox(height: 8.0),
            Text(
              _footer(context, game),
              style: TextTheme.of(context).bodySmall?.copyWith(color: textShade(context, 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One seat of a row: the piece that side plays, who is in it, and what its clock reads.
///
/// The avatar is the side's own general, drawn by [XiangqiPieceAvatar] — the same piece the board
/// draws and the same one the online game screen's own player rows draw, so a name and the pieces
/// it stands for cannot drift apart.
class const _SeatLine({
  required final XiangqiSide side,
  required final XiangqiLivePlayer player,
  required final bool isTurn,
  required final XiangqiBoardStyle style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final seconds = player.secondsLeft;
    return Row(
      children: [
        XiangqiPieceAvatar(side: side, size: 28, style: style),
        const SizedBox(width: 8.0),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  player.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    // The seat that is thinking is the one the eye should land on; the other is
                    // shaded back, the way the online game screen shades its own two rows.
                    color: isTurn ? null : textShade(context, 0.6),
                  ),
                ),
              ),
              if (player.rating != null) ...[
                const SizedBox(width: 4.0),
                Text(
                  '${player.rating}',
                  style: TextStyle(fontSize: 14, color: textShade(context, 0.7)),
                ),
              ],
              if (player.isBot) ...[
                const SizedBox(width: 5.0),
                Text(
                  context.l10n.computer,
                  style: TextStyle(fontSize: 14, color: context.lichessColors.fancy),
                ),
              ],
            ],
          ),
        ),
        if (seconds != null)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              _clockText(seconds),
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isTurn ? null : textShade(context, 0.6),
              ),
            ),
          ),
      ],
    );
  }
}

/// What the two seats are playing: the time control, how far along, and whether it counts.
///
/// The time control is written the way the app writes every other one — `10+0`, minutes and
/// increment — and the move count is the ply count the server sent, halved and rounded up, because
/// a player counts moves in pairs and the server counts them one at a time.
String _footer(BuildContext context, XiangqiLiveGame game) {
  final minutes = game.gameTimeSeconds ~/ 60;
  final parts = <String>[
    '$minutes+${game.incrementSeconds}',
    context.l10n.mobileXiangqiWatchMoves((game.movesCount + 1) ~/ 2),
    if (game.isRated) context.l10n.rated,
  ];
  return parts.join(' · ');
}

/// [seconds] as a clock reading: `m:ss`, or `h:mm:ss` once there is an hour on it.
///
/// The same shape [Clock] draws, written out here because a row is not a clock: the clock widget
/// carries a background and a size meant for a board's own score sheet, and twenty of them in a
/// list would read as twenty score sheets.
String _clockText(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secs';
  }
  return '$minutes:$secs';
}

/// What the list says when nobody is playing.
class const _NoGames() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.mobileXiangqiWatchNoGames, textAlign: TextAlign.center);
  }
}
