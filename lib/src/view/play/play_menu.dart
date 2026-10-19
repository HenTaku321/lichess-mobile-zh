import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/offline_computer/computer_game_screen.dart';
import 'package:lichess_mobile/src/view/over_the_board/over_the_board_screen.dart';
import 'package:lichess_mobile/src/view/play/correspondence_challenges_screen.dart';
import 'package:lichess_mobile/src/view/play/create_challenge_bottom_sheet.dart';
import 'package:lichess_mobile/src/view/play/create_game_widget.dart';
import 'package:lichess_mobile/src/view/play/tournaments_hub_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_new_game_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_ui/material_ui.dart';

class const PlayMenu() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(lichessConnectionStatusProvider);

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
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(TournamentsHubScreen.buildRoute());
              },
              leading: const Icon(LichessIcons.tournament_cup),
              title: Text(context.l10n.arenaArenaTournaments),
            ),
            ListTile(
              onTap: () {
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(ComputerGameScreen.buildRoute());
              },
              leading: const Icon(Icons.memory),
              title: Text(context.l10n.playAgainstComputer),
            ),
            ListTile(
              onTap: () {
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(OverTheBoardScreen.buildRoute());
              },
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(context.l10n.mobileOverTheBoard),
            ),
            // A game against somebody on xiangqi.com, beside the one against the app's own engine.
            // Two rows and not a picker: lichess and xiangqi.com are two services with two accounts,
            // and the row that starts a game on one of them is not the other's other half — the same
            // reason the master-games database has a row of its own. See `xiangqi_new_game_screen.dart`.
            ListTile(
              onTap: () {
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(XiangqiNewGameScreen.buildRoute());
              },
              leading: const Icon(Icons.grid_on),
              title: Text('${context.l10n.mobileXiangqi} · ${context.l10n.createAGame}'),
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
