import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/over_the_board/over_the_board_screen.dart';
import 'package:lichess_mobile/src/view/play/correspondence_challenges_screen.dart';
import 'package:lichess_mobile/src/view/play/create_challenge_bottom_sheet.dart';
import 'package:lichess_mobile/src/view/play/create_game_widget.dart';
import 'package:lichess_mobile/src/view/tournament/tournament_list_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_ui/material_ui.dart';

class const PlayMenu() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(lichessConnectionStatusProvider);
    // Xiangqi is offered only where the build has Pikafish, which is the whole of what it plays
    // against: without it the board would take the player's first move and then wait for an answer
    // that is never coming. See `EngineAvailability.pikafish`. The gate sits on the picker's choices
    // rather than on a row of its own, so that a build without Pikafish still plays chess.
    final xiangqiAvailable = ref.watch(engineAvailabilityProvider).pikafish;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: CreateGameWidget(),
        ),
        _Section(
          children: [
            ListTile(
              enabled: connectionStatus == LichessConnectionStatus.online,
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  builder: (context) {
                    return const CreateChallengeBottomSheet(user: null);
                  },
                );
              },
              leading: const Icon(Icons.person),
              title: Text(context.l10n.challengeAFriend),
            ),
            ListTile(
              enabled: connectionStatus == LichessConnectionStatus.online,
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(CorrespondenceChallengesScreen.buildRoute());
              },
              leading: Icon(Perf.correspondence.icon),
              title: Text(context.l10n.correspondence),
            ),
            ListTile(
              enabled: connectionStatus == LichessConnectionStatus.online,
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);

                Navigator.of(context).push(TournamentListScreen.buildRoute());
              },
              leading: const Icon(LichessIcons.tournament_cup),
              title: Text(context.l10n.arenaArenaTournaments),
            ),
            ListTile(
              onTap: () async {
                // Chess and xiangqi share this one row, and the picker below decides which is
                // played: they are two games of equal standing, and giving xiangqi a row of its own
                // would say it was the lesser one.
                final choices = [
                  _OfflineOpponent.chess,
                  if (xiangqiAvailable) _OfflineOpponent.xiangqi,
                ];
                _OfflineOpponent? choice;
                // The picker has to come before the sheet is popped: the sheet's context is still
                // alive to host it, and a player who dismisses it without choosing is left where
                // they were, with nothing to navigate to.
                await showChoicePicker<_OfflineOpponent>(
                  context,
                  title: Text(context.l10n.playAgainstComputer),
                  choices: choices,
                  selectedItem: .chess,
                  labelBuilder: (opponent) => Text(switch (opponent) {
                    .chess => context.l10n.mobileChess,
                    .xiangqi => context.l10n.mobileXiangqi,
                  }),
                  onSelectedItemChanged: (opponent) => choice = opponent,
                );
                if (!context.mounted) return;
                final selected = choice;
                if (selected == null) return;
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(switch (selected) {
                  .chess => OfflineComputerGameScreen.buildRoute(),
                  .xiangqi => XiangqiGameScreen.buildRoute(),
                });
              },
              leading: const Icon(Icons.memory),
              title: Text(context.l10n.playAgainstComputer),
            ),
            ListTile(
              onTap: () async {
                // Chess and xiangqi share this row exactly as they share the one above it, and for
                // the same reason: playing over the board is a way of playing rather than a game,
                // so it is offered for both instead of owned by either. Unlike the computer row,
                // the choice is *not* gated on `engineAvailabilityProvider.pikafish`: over the
                // board both sides are a person's, nothing is ever searched for, and a build
                // without Pikafish plays this one as well as any other.
                _OtbGame? choice;
                // As above, the picker comes before the sheet is popped so that the sheet's own
                // context can host it, and a player who dismisses it is left where they were.
                await showChoicePicker<_OtbGame>(
                  context,
                  title: Text(context.l10n.mobileOverTheBoard),
                  choices: _OtbGame.values,
                  selectedItem: .chess,
                  labelBuilder: (game) => Text(switch (game) {
                    .chess => context.l10n.mobileChess,
                    .xiangqi => context.l10n.mobileXiangqi,
                  }),
                  onSelectedItemChanged: (game) => choice = game,
                );
                if (!context.mounted) return;
                final selected = choice;
                if (selected == null) return;
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(switch (selected) {
                  .chess => OverTheBoardScreen.buildRoute(),
                  .xiangqi => XiangqiOverTheBoardScreen.buildRoute(),
                });
              },
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(context.l10n.mobileOverTheBoard),
            ),
          ],
        ),
      ],
    );
  }
}

class const _Section({required final List<Widget> children}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListSection(hasLeading: true, materialFilledCard: true, children: children);
  }
}

/// Which game the player wants the computer to play.
///
/// The two are offered side by side by the one "Play against the computer" entry, so neither reads
/// as the app's main game and the other as an extra: the game is a choice inside the entry, not a
/// property of it.
enum _OfflineOpponent() {
  chess,
  xiangqi,
}

/// Which game the over-the-board screen is set up for.
///
/// The same two, offered by the same one entry and in the same way: playing over the board is a way
/// of playing rather than a game of its own, so which game it is set up for is a choice inside the
/// entry here too.
enum _OtbGame() {
  chess,
  xiangqi,
}
