import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/team/team_providers.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_screen.dart';
import 'package:lichess_mobile/src/view/clock/clock_tool_screen.dart';
import 'package:lichess_mobile/src/view/explorer/opening_explorer_screen.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/more/import_pgn_screen.dart';
import 'package:lichess_mobile/src/view/relation/friend_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/team/team_updates_screen.dart';
import 'package:lichess_mobile/src/view/user/player_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class const MoreTabScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          ref.read(currentBottomTabProvider.notifier).state = BottomTab.home;
        }
      },
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          title: Theme.of(context).platform == TargetPlatform.iOS
              ? AppBarLichessTitle(
                  iconSize: Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24,
                )
              : const AppBarLichessTitle(),
          centerTitle: false,
          titleTextStyle: Theme.of(context).platform == TargetPlatform.iOS
              ? Theme.of(context).textTheme.headlineSmall
              : null,
          actions: const [AccountMenuButton()],
        ),
        body: const _Body(),
      ),
    );
  }
}

class const _Body() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final authUser = ref.watch(authControllerProvider);
    // Xiangqi's analysis board runs Pikafish and nothing else, so it is offered only where the build
    // has it. See the Analysis row below, and `EngineAvailability.pikafish`.
    final xiangqiAvailable = ref.watch(engineAvailabilityProvider).pikafish;

    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        controller: moreScrollController,
        children: [
          ListSection(
            header: SettingsSectionTitle(context.l10n.tools),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.importPgn),
                onTap: () => Navigator.of(context).push(ImportPgnScreen.buildRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.biotech_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.analysis),
                onTap: () async {
                  // Chess and xiangqi share this one row, and the picker below decides which of
                  // them is analysed: they are two games of equal standing, and giving xiangqi a row
                  // of its own would say it was the lesser one. See the play menu's two rows for the
                  // same arrangement — `lib/src/view/play/play_menu.dart`.
                  //
                  // Xiangqi is offered only where the build has Pikafish, which is the whole of what
                  // an analysis board's engine is there: chess's own engine ships with the app, and a
                  // xiangqi board whose engine could not start would open onto an error and a verdict
                  // that never comes. The gate sits on the picker's choices rather than on a row of
                  // its own, so that a build without Pikafish still analyses chess.
                  final choices = [
                    _AnalysisGame.chess,
                    if (xiangqiAvailable) _AnalysisGame.xiangqi,
                  ];
                  _AnalysisGame? choice;
                  await showChoicePicker<_AnalysisGame?>(
                    context,
                    title: Text(context.l10n.analysis),
                    choices: choices,
                    // Nothing is ticked before the player ticks it, and the type is nullable to say
                    // so: this picker is a question with two answers rather than a setting being
                    // looked at, and the Material dialog's radios ignore a tap on the choice that is
                    // already selected — a default here would be an answer that could not be given.
                    // The play menu's pickers are the same kind of question, and are left unticked
                    // for the same reason.
                    selectedItem: null,
                    labelBuilder: (game) => Text(switch (game) {
                      .chess => context.l10n.mobileChess,
                      .xiangqi => context.l10n.mobileXiangqi,
                      // Never built — the choices are the two games — but the picker is instantiated
                      // at a nullable type, so the switch has to answer for the null.
                      null => '',
                    }),
                    onSelectedItemChanged: (game) => choice = game,
                  );
                  if (!context.mounted) return;
                  final selected = choice;
                  if (selected == null) return;
                  Navigator.of(context, rootNavigator: true).push(switch (selected) {
                    .chess => AnalysisScreen.buildRoute(
                      const AnalysisOptions.standalone(variant: Variant.standard),
                    ),
                    .xiangqi => XiangqiAnalysisScreen.buildRoute(),
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.openingExplorer),
                enabled: isOnline,
                onTap: () {
                  if (authUser == null) {
                    showSnackBar(context, context.l10n.youNeedAnAccountToDoThat);
                    return;
                  }

                  Navigator.of(context, rootNavigator: true).push(
                    OpeningExplorerScreen.buildRoute(
                      const AnalysisOptions.pgn(
                        id: StringId('standalone_opening_explorer'),
                        orientation: Side.white,
                        pgn: '',
                        isComputerAnalysisAllowed: false,
                        variant: Variant.standard,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.boardEditor),
                onTap: () async {
                  // Chess and xiangqi share this one row for the reason the Analysis row above shares
                  // its own: a board to put pieces on is the same tool in either game, and a row each
                  // would say one of them was the lesser. See that row for the whole of it.
                  //
                  // Both are offered in every build, which is where this row parts company with the
                  // one above. An analysis board is the engine's, so a build without Pikafish has no
                  // xiangqi analysis to offer; an editor is a board and a FEN, and can be left with
                  // one without an engine ever starting — the same reason the play menu's
                  // over-the-board row is ungated. The edge is the xiangqi editor's "continue to
                  // analysis" exit, which would not open in a build without Pikafish: two of its three
                  // exits are still fine, no build that exists today is without it (both
                  // `EngineAvailability` values declare it), and if one ever appears the exit is what
                  // to fix rather than this row.
                  final choices = [_EditorGame.chess, _EditorGame.xiangqi];
                  _EditorGame? choice;
                  await showChoicePicker<_EditorGame?>(
                    context,
                    title: Text(context.l10n.boardEditor),
                    choices: choices,
                    // Left unticked, as the Analysis picker's is: a question with two answers rather
                    // than a setting being looked at, and the Material dialog's radios ignore a tap
                    // on the choice that is already selected.
                    selectedItem: null,
                    labelBuilder: (game) => Text(switch (game) {
                      .chess => context.l10n.mobileChess,
                      .xiangqi => context.l10n.mobileXiangqi,
                      // Never built, but the picker is instantiated at a nullable type and the
                      // switch has to answer for the null.
                      null => '',
                    }),
                    onSelectedItemChanged: (game) => choice = game,
                  );
                  if (!context.mounted) return;
                  final selected = choice;
                  if (selected == null) return;
                  Navigator.of(context, rootNavigator: true).push(switch (selected) {
                    .chess => BoardEditorScreen.buildRoute((
                      initialVariant: Variant.standard,
                      initialFen: null,
                      initialOrientation: null,
                    )),
                    .xiangqi => XiangqiBoardEditorScreen.buildRoute(),
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.alarm_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.clock),
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(ClockToolScreen.buildRoute());
                },
              ),
            ],
          ),
          ListSection(
            header: SettingsSectionTitle(context.l10n.community),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.groups_3_outlined),
                title: Text(context.l10n.players),
                enabled: isOnline,
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(PlayerScreen.buildRoute());
                },
              ),
              if (authUser != null)
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(context.l10n.friends),
                  enabled: isOnline,
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(FriendScreen.buildRoute());
                  },
                ),
            ],
          ),
          const _AccountSection(),
          if (Theme.of(context).platform == TargetPlatform.android)
            ListSection(
              hasLeading: true,
              children: [
                ListTile(
                  leading: PatronIcon(color: 10, size: IconTheme.of(context).size),
                  title: Text(context.l10n.patronDonate),
                  subtitle: Text(context.l10n.patronBecomePatron),
                  enabled: isOnline,
                  onTap: () {
                    launchUrl(Uri.parse('https://lichess.org/patron'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(context.l10n.about),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(AboutScreen.buildRoute());
                  },
                ),
              ],
            ),
          Padding(
            padding: Styles.bodySectionPadding,
            child: LichessMessage(style: TextTheme.of(context).bodyMedium),
          ),
        ],
      ),
    );
  }
}

class const _AccountSection() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final account = ref.watch(accountProvider);
    final authUser = ref.watch(authControllerProvider);
    final kidMode = account.value?.kid ?? false;
    final unreadMessages = ref.watch(unreadMessagesProvider).value?.unread ?? 0;
    final unreadTeamUpdates = ref.watch(unreadTeamUpdatesCountProvider).value ?? 0;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final user = authUser?.user;

    return ListSection(
      header: user != null ? SettingsSectionTitle(user.name) : null,
      hasLeading: true,
      children: [
        if (user != null) ...[
          ListTile(
            leading: const Icon(Icons.person_outlined),
            title: Text(context.l10n.profile),
            trailing: isIOS ? const CupertinoListTileChevron() : null,
            enabled: isOnline,
            onTap: () {
              ref.invalidate(accountProvider);
              Navigator.of(context).push(ProfileScreen.buildRoute());
            },
          ),
          if (!kidMode) ...[
            ListTile(
              leading: Badge.count(
                isLabelVisible: unreadMessages > 0,
                count: unreadMessages,
                child: const Icon(Icons.mail_outline),
              ),
              title: Text(context.l10n.inbox),
              trailing: isIOS ? const CupertinoListTileChevron() : null,
              enabled: isOnline,
              onTap: () {
                Navigator.of(context).push(ContactsScreen.buildRoute());
              },
            ),
            ListTile(
              leading: Badge.count(
                isLabelVisible: unreadTeamUpdates > 0,
                count: unreadTeamUpdates,
                child: const Icon(Icons.groups_outlined),
              ),
              title: Text(context.l10n.teamTeamUpdates),
              trailing: isIOS ? const CupertinoListTileChevron() : null,
              enabled: isOnline,
              onTap: () {
                Navigator.of(context).push(TeamUpdatesScreen.buildRoute());
              },
            ),
          ],
        ],
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.l10n.settingsSettings),
          trailing: isIOS ? const CupertinoListTileChevron() : null,
          onTap: () {
            Navigator.of(context).push(SettingsScreen.buildRoute());
          },
        ),
      ],
    );
  }
}

/// The two games this app will take a position apart on.
///
/// The Analysis row offers both rather than a row each: a board to analyse on is the same tool in
/// either game, and the chess one is no more of an analysis board than the xiangqi one is. Nothing
/// is ticked when it opens, as in the play menu's own two pickers: each of them asks a question with
/// two answers, and neither has a default to give.
enum _AnalysisGame() {
  chess,
  xiangqi,
}

/// The two games this app will build a position in.
///
/// The Board editor row offers both rather than a row each, for the reason [_AnalysisGame] above
/// does: a board to put pieces on is the same tool in either game. Unlike that one, neither is ever
/// left out — see the row's own comment — so this enum has the two choices it names and nothing to
/// say about which of them a build can offer.
enum _EditorGame() {
  chess,
  xiangqi,
}
