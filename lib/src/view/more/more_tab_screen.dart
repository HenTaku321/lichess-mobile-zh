import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/team/team_providers.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_hub_screen.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_hub_screen.dart';
import 'package:lichess_mobile/src/view/clock/clock_tool_screen.dart';
import 'package:lichess_mobile/src/view/explorer/opening_explorer_screen.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/more/import_pgn_screen.dart';
import 'package:lichess_mobile/src/view/relation/friends_hub_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/team/team_updates_screen.dart';
import 'package:lichess_mobile/src/view/user/leaderboard_hub_screen.dart';
import 'package:lichess_mobile/src/view/user/player_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_database_screen.dart';
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
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(AnalysisHubScreen.buildRoute());
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
                leading: const Icon(Icons.extension_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.boardEditor),
                onTap: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(BoardEditorHubScreen.buildRoute());
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.mobileXiangqiDatabase),
                enabled: isOnline,
                onTap: () {
                  // A row of its own rather than a picker like the ones above, and deliberately:
                  // there is nothing on lichess this is the other half of. The master-games
                  // database is a library of whole games by named players, and lichess's nearest
                  // neighbour — the opening explorer — is a different question asked of a
                  // different corpus. A picker would be claiming the two were one feature.
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(XiangqiDatabaseScreen.buildRoute());
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
                leading: const Icon(Icons.leaderboard_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.leaderboard),
                onTap: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(LeaderboardHubScreen.buildRoute());
                },
              ),
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
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: Text(context.l10n.friends),
                enabled: isOnline,
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(FriendsHubScreen.buildRoute());
                },
              ),
              // The one community this app has that lichess does not: xiangqi.com's own rooms. It
              // sits beside the lichess ones rather than in a section of its own because it is the
              // same thing to a reader — somewhere to talk — and a section called "xiangqi" would
              // be a second menu for one row.
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(context.l10n.mobileXiangqiChat),
                enabled: isOnline,
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(XiangqiChatScreen.buildRoute());
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
