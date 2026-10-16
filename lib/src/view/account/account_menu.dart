import 'package:auto_size_text/auto_size_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/team/team_providers.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/http_network_image.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/lichess_assets.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_error.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_options.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/team/team_updates_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_saved_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Account menu screen opened by [AccountMenuButton].
///
/// On Android it is pushed as a full-screen page. On iOS it is presented
/// inside a [CupertinoSheetRoute] with nested navigation.
class const AccountMenuScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return buildScreenRoute(screen: const AccountMenuScreen());
    }

    return PageRouteBuilder<void>(
      pageBuilder: (_, a, b) => const AccountMenuScreen(),
      transitionsBuilder: (_, animation, b, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  ConsumerState<AccountMenuScreen> createState() => _AccountMenuScreenState();
}

class _AccountMenuScreenState()
    extends ConsumerState<AccountMenuScreen>
    with WidgetsBindingObserver {
  bool _errorLoadingFlair = false;
  bool _pendingKidModeRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingKidModeRefresh) {
      _pendingKidModeRefresh = false;
      ref.invalidate(accountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(defaultClientProvider);
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final signInState = ref.watch(signInMutation);
    final signOutState = ref.watch(signOutMutation);

    ref.listen(signInMutation, (_, next) => showSignInErrorSnackBar(context, next));
    final account = ref.watch(accountProvider);
    final authUser = ref.watch(authControllerProvider);
    final xiangqiSession = ref.watch(xiangqiAuthControllerProvider);
    final kidMode = account.value?.kid ?? false;
    final LightUser? user = account.value?.lightUser ?? authUser?.user;
    final unreadMessages = ref.watch(unreadMessagesProvider).value?.unread ?? 0;
    final unreadTeamUpdates = ref.watch(unreadTeamUpdatesCountProvider).value ?? 0;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(context.l10n.mobileAccount),
        automaticallyImplyLeading: Theme.of(context).platform == TargetPlatform.iOS,
        actions: [
          if (Theme.of(context).platform != TargetPlatform.iOS)
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      body: ListView(
        children: [
          if (user != null)
            ListSection(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  leading: switch (account) {
                    AsyncData(:final value) =>
                      value == null
                          ? const Icon(Icons.account_circle_outlined, size: 30)
                          : CircleAvatar(
                              radius: 20,
                              foregroundImage: value.flair != null && !_errorLoadingFlair
                                  ? HttpNetworkImage(lichessFlairSrc(value.flair!), client)
                                  : null,
                              onForegroundImageError: value.flair != null
                                  ? (error, _) => setState(() => _errorLoadingFlair = true)
                                  : null,
                              backgroundColor: value.flair == null || _errorLoadingFlair
                                  ? null
                                  : ColorScheme.of(context).surfaceContainer,
                              child: value.flair == null || _errorLoadingFlair
                                  ? Text(value.initials)
                                  : null,
                            ),
                    _ => const Icon(Icons.account_circle_outlined, size: 30),
                  },
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: AutoSizeText(
                    user.name,
                    style: Styles.callout,
                    maxLines: 1,
                    minFontSize: 14,
                    maxFontSize: 18,
                    overflow: TextOverflow.ellipsis,
                  ),
                  enabled: isOnline,
                  onTap: () {
                    ref.invalidate(accountProvider);
                    _navigate(context, ProfileScreen.buildRoute());
                  },
                ),
                if (kidMode)
                  ListTile(
                    textColor: Theme.of(context).colorScheme.primary,
                    iconColor: Theme.of(context).colorScheme.primary,
                    leading: const Icon(Symbols.sentiment_satisfied, weight: 600),
                    title: Text(
                      context.l10n.kidModeIsEnabled,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      _pendingKidModeRefresh = true;
                      launchUrl(lichessUri('/account/kid'));
                    },
                  ),
              ],
            )
          else ...[
            Center(
              child: FilledButton(
                onPressed: isOnline
                    ? switch (signInState) {
                        MutationPending() => null,
                        _ => () => showSignInOptions(context, ref),
                      }
                    : null,
                child: Text(context.l10n.signIn),
              ),
            ),
          ],
          // The xiangqi.com identity, kept as its own section so it reads beside the lichess one
          // above rather than inside the "things you can do" list below.
          ListSection(
            children: [
              switch (xiangqiSession) {
                // No session yet: the row is the way in.
                null => ListTile(
                  leading: const Icon(Icons.grid_on),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.mobileXiangqiSignIn),
                  enabled: isOnline,
                  onTap: () => _navigate(context, XiangqiLoginScreen.buildRoute()),
                ),
                // A guest is not a signed-in account, so the row says who it is and offers the way
                // to a real one at the end.
                final XiangqiSession session when session.isGuest => ListTile(
                  leading: const Icon(Icons.grid_on),
                  trailing: TextButton(
                    onPressed: isOnline
                        ? () => _navigate(context, XiangqiLoginScreen.buildRoute())
                        : null,
                    child: Text(context.l10n.signIn),
                  ),
                  title: Text(context.l10n.mobileXiangqiGuest),
                ),
                // A real account: its name, its ratings and where it is, and a tap that opens its
                // profile. The account endpoint is verified and is what the subtitle is read from,
                // and the same endpoint is what the profile behind the tap is built on — so the row
                // and the screen it opens cannot disagree about who this is. Signing out lives on
                // that screen, where it is one action among the account's own rather than the only
                // thing the row can do.
                final XiangqiSession session => ListTile(
                  leading: const Icon(Icons.grid_on),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(session.name),
                  subtitle: _xiangqiUserSubtitle(
                    context,
                    ref.watch(xiangqiUserProvider(session.name)),
                  ),
                  enabled: isOnline,
                  onTap: () => _navigate(context, XiangqiProfileScreen.buildRoute(session.name)),
                ),
              },
              // What xiangqi.com has told this account, and what it has made on it. Both are
              // offered only to a real account, and not to a guest: a guest session is one the app
              // made for a visitor, and neither the notifications behind it nor the content in it
              // would be anything of the visitor's own.
              if (xiangqiSession != null && !xiangqiSession.isGuest) ...[
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.notifications),
                  enabled: isOnline,
                  onTap: () => _navigate(context, XiangqiNotificationsScreen.buildRoute()),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_special_outlined),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.mobileXiangqiSaved),
                  enabled: isOnline,
                  onTap: () => _navigate(context, XiangqiSavedScreen.buildRoute()),
                ),
              ],
            ],
          ),
          ListSection(
            children: [
              if (user != null && account.hasValue && !kidMode) ...[
                ListTile(
                  leading: Badge.count(
                    isLabelVisible: unreadMessages > 0,
                    count: unreadMessages,
                    child: const Icon(Icons.mail_outline),
                  ),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.inbox),
                  enabled: isOnline,
                  onTap: () {
                    _navigate(context, ContactsScreen.buildRoute());
                  },
                ),
                ListTile(
                  leading: Badge.count(
                    isLabelVisible: unreadTeamUpdates > 0,
                    count: unreadTeamUpdates,
                    child: const Icon(Icons.groups_outlined),
                  ),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.teamTeamUpdates),
                  enabled: isOnline,
                  onTap: () {
                    _navigate(context, TeamUpdatesScreen.buildRoute());
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.settingsSettings),
                onTap: () {
                  _navigate(context, SettingsScreen.buildRoute());
                },
              ),
              if (user != null)
                switch (signOutState) {
                  MutationPending() => const ListTile(
                    leading: Icon(Icons.logout_outlined),
                    enabled: false,
                    title: Center(child: ButtonLoadingIndicator()),
                  ),
                  _ => ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: Text(context.l10n.logOut),
                    enabled: isOnline,
                    onTap: () => _showSignOutConfirmDialog(context, ref),
                  ),
                },
            ],
          ),
          ListSection(
            children: [
              if (Theme.of(context).platform == TargetPlatform.android)
                ListTile(
                  leading: Icon(
                    LichessIcons.patron,
                    semanticLabel: context.l10n.patronLichessPatron,
                  ),
                  title: Text(context.l10n.patronDonate),
                  enabled: isOnline,
                  onTap: () => launchUrl(Uri.parse('https://lichess.org/patron')),
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.about),
                onTap: () {
                  _navigate(context, AboutScreen.buildRoute());
                },
              ),
            ],
          ),
          const SocketPingRatingListTile(),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, Route<dynamic> route) {
    Navigator.of(context).push(route);
  }

  /// Confirms signing out of the xiangqi.com account.
  ///
  /// Reuses the lichess "log out" wording (`context.l10n.logOut`) rather than inventing a new word
  /// for the same act, and drops straight through: unlike a lichess sign-out there is no
  /// server-side token to revoke, so there is nothing to wait on.

  /// The subtitle of the signed-in xiangqi.com row: the account's ratings, then whether it is
  /// online and where it is.
  ///
  /// One line, and only when there is a profile to read: while the lookup is loading and after it
  /// has failed the row is drawn without a subtitle, so a slow or refused request leaves the name
  /// where it was rather than a spinner or an error where the ratings go. The ratings are the
  /// *short* perf labels — `Bullet 543 · Rapid 584 · Corresp. 600 · Puzzle 1235` — because the
  /// subtitle has one line to say four numbers in, and a speed the account has never played is
  /// left out rather than shown as a zero.
  ///
  /// The perf labels are the lichess ones (`Perf.shortLabel`), reused rather than re-typed: they
  /// name the same four speeds, and the account row is not the place to say them differently.
  Widget? _xiangqiUserSubtitle(BuildContext context, AsyncValue<XiangqiUserProfile> profile) {
    final value = profile.value;
    if (value == null) return null;

    final l10n = context.l10n;
    final ratings = [
      if (value.bulletRating != null) '${Perf.bullet.shortLabel(l10n)} ${value.bulletRating}',
      if (value.rapidRating != null) '${Perf.rapid.shortLabel(l10n)} ${value.rapidRating}',
      if (value.dailyRating != null) '${Perf.correspondence.shortLabel(l10n)} ${value.dailyRating}',
      if (value.puzzleRating != null) '${Perf.puzzle.shortLabel(l10n)} ${value.puzzleRating}',
    ];
    final status = [
      if (value.isOnline) l10n.online else l10n.offline,
      if (value.countryName != null) value.countryName!,
    ];

    return Text(
      [...ratings, status.join(' · ')].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showSignOutConfirmDialog(BuildContext context, WidgetRef ref) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      showCupertinoActionSheet<void>(
        context: context,
        actions: [
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.logOut),
            isDestructiveAction: true,
            onPressed: () async {
              await signOutMutation.run(ref, (tsx) async {
                await tsx.get(authControllerProvider.notifier).signOut();
              });
            },
          ),
        ],
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(context.l10n.logOut),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await signOutMutation.run(ref, (tsx) async {
                    await tsx.get(authControllerProvider.notifier).signOut();
                  });
                },
                child: Text(context.l10n.mobileOkButton),
              ),
            ],
          );
        },
      );
    }
  }
}

/// Avatar button that opens the account menu.
///
/// On Android opens [AccountMenuScreen] as a full-screen page sliding from the
/// right. On iOS opens the same screen inside a [CupertinoSheetRoute] with
/// nested navigation.
class const AccountMenuButton({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState() extends ConsumerState<AccountMenuButton> {
  bool _errorLoadingFlair = false;

  static const _materialAnonIconSize = 30.0;
  static const _cupertinoAnonIconSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final kidMode = account.value?.kid ?? false;
    final unreadMessages = ref.watch(unreadMessagesProvider).value?.unread ?? 0;
    final client = ref.watch(defaultClientProvider);

    void openMenu() {
      Navigator.of(context).push(AccountMenuScreen.buildRoute(context));
    }

    return switch (account) {
      AsyncData(:final value) => Badge.count(
        offset: const Offset(-4, 0),
        count: unreadMessages,
        isLabelVisible: !kidMode && unreadMessages > 0,
        child: IconButton(
          tooltip: value == null ? context.l10n.signIn : value.username,
          icon: value == null
              ? Icon(
                  Icons.account_circle_outlined,
                  size: Theme.of(context).platform == TargetPlatform.iOS
                      ? _cupertinoAnonIconSize
                      : _materialAnonIconSize,
                )
              : CircleAvatar(
                  radius:
                      (Theme.of(context).platform == TargetPlatform.iOS
                          ? _cupertinoAnonIconSize / 2
                          : _materialAnonIconSize / 2) +
                      1,
                  foregroundImage: value.flair != null && !_errorLoadingFlair
                      ? HttpNetworkImage(lichessFlairSrc(value.flair!), client)
                      : null,
                  onForegroundImageError: value.flair != null
                      ? (error, _) => setState(() => _errorLoadingFlair = true)
                      : null,
                  backgroundColor: value.flair == null || _errorLoadingFlair
                      ? null
                      : ColorScheme.of(context).surfaceContainer,
                  child: value.flair == null || _errorLoadingFlair ? Text(value.initials) : null,
                ),
          onPressed: openMenu,
        ),
      ),
      _ => IconButton(
        icon: Icon(
          Icons.account_circle_outlined,
          size: Theme.of(context).platform == TargetPlatform.iOS
              ? _cupertinoAnonIconSize
              : _materialAnonIconSize,
        ),
        tooltip: context.l10n.signIn,
        onPressed: openMenu,
      ),
    };
  }
}

/// About screen with links to various lichess resources and legal information.
class const AboutScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() {
    return buildScreenRoute(screen: const AboutScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final packageInfo = ref.read(preloadedDataProvider).requireValue.packageInfo;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.about)),
      body: ListView(
        children: [
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.info_outlined),
                title: Text(context.l10n.aboutX('Lichess')),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/about'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.feedback_outlined),
                title: Text(context.l10n.mobileFeedbackButton),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/contact'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.article_outlined),
                title: Text(context.l10n.termsOfService),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/terms-of-service'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(context.l10n.privacyPolicy),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/privacy'));
                },
              ),
            ],
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                enabled: isOnline,
                leading: const Icon(Symbols.database),
                title: Text(context.l10n.database),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://database.lichess.org'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.code_outlined),
                title: Text(context.l10n.sourceCode),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/source'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(context.l10n.contribute),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/help/contribute'));
                },
              ),
              ListTile(
                enabled: isOnline,
                leading: const Icon(Icons.star_border_outlined),
                title: Text(context.l10n.thankYou),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/thanks'));
                },
              ),
            ],
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.copyright_outlined),
                title: Text(context.l10n.mobileViewLicenses),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'Lichess',
                    applicationVersion: packageInfo.version,
                    applicationIcon: const Icon(LichessIcons.logo_lichess),
                  );
                },
              ),
            ],
          ),
          Padding(
            padding: Styles.bodySectionPadding,
            child: Text('v${packageInfo.version}', style: TextTheme.of(context).bodySmall),
          ),
        ],
      ),
    );
  }
}
