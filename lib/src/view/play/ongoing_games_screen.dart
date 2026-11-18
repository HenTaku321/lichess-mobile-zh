import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game_entry.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/game/offline_correspondence_games_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_ongoing_game_preview.dart';
import 'package:lichess_mobile/src/widgets/board_preview.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';

class const OngoingGamesScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const OngoingGamesScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(availableOngoingGamesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.nbGamesInPlay(games.length))),
      body: ListView(
        children: [
          const SizedBox(height: 8.0),
          for (final game in games) OngoingEntryPreview(key: ValueKey(game.rowKey), entry: game),
        ],
      ),
    );
  }
}

class const OngoingEntryPreview({
  required final OngoingGameEntry entry,
  final EdgeInsetsGeometry? padding,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => switch (entry) {
    ChessOngoingGame(:final game) => OngoingGamePreview(game: game, padding: padding),
    XiangqiOngoingGame(:final game) => XiangqiOngoingGamePreview(game: game, padding: padding),
    StoredCorrespondenceEntry(:final game, :final lastModified) => OfflineCorrespondenceGamePreview(
      game: game,
      lastModified: lastModified,
    ),
  };
}

class const OngoingGamePreview({
  required final OngoingGame game,
  final EdgeInsetsGeometry? padding,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SmallBoardPreview(
      padding: padding,
      orientation: game.orientation,
      lastMove: game.lastMove,
      fen: game.fen,
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          UserFullNameWidget.player(
            user: game.opponent,
            rating: game.opponentRating,
            aiLevel: game.opponentAiLevel,
            style: Styles.boardPreviewTitle,
          ),
          Icon(
            game.perf.icon,
            size: 34,
            color: game.isMyTurn
                ? context.lichessColors.brag
                : DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.5),
          ),
          if (game.isMyTurn && game.secondsLeft != null)
            Text(
              relativeDate(context.l10n, DateTime.now().add(Duration(seconds: game.secondsLeft!))),
            )
          else
            Text(game.isMyTurn ? context.l10n.yourTurn : context.l10n.waitingForOpponent),
        ],
      ),
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          GameScreen.buildRoute(
            source: ExistingGameSource(game.fullId),
            loadingPosition: (
              variant: game.variant,
              fen: game.fen,
              orientation: game.orientation,
              lastMove: game.lastMove,
            ),
          ),
        );
      },
    );
  }
}
