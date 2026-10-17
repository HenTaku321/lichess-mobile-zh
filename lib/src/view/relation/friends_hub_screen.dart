import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/relation/online_friends.dart';
import 'package:lichess_mobile/src/model/relation/relation_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social_repository.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_options.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:lichess_mobile/src/view/relation/friend_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/source_preview_block.dart';
import 'package:material_ui/material_ui.dart';

/// Friends from both accounts, with each account's own sign-in state.
class const FriendsHubScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const FriendsHubScreen());

  @override
  ConsumerState<FriendsHubScreen> createState() => _FriendsHubScreenState();
}

class _FriendsHubScreenState() extends ConsumerState<FriendsHubScreen> {
  bool _lichessExpanded = false;
  bool _xiangqiExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lichessUser = ref.watch(authControllerProvider)?.user;
    final xiangqiSession = ref.watch(xiangqiAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.friends)),
      body: ListView(
        children: [
          SourcePreviewBlock(
            leading: const Icon(Icons.groups_3_outlined),
            title: const Text('Lichess'),
            expandedState: _lichessExpanded,
            onToggle: () => setState(() => _lichessExpanded = !_lichessExpanded),
            preview: lichessUser == null
                ? _SignInRow(onTap: () => showSignInOptions(context, ref))
                : _LichessFriends(accountName: lichessUser.name, expanded: false),
            expanded: lichessUser == null
                ? _SignInRow(onTap: () => showSignInOptions(context, ref))
                : _LichessFriends(accountName: lichessUser.name, expanded: true),
          ),
          const Divider(height: 1),
          SourcePreviewBlock(
            leading: const Icon(Icons.grid_on),
            title: const Text('Xiangqi.com'),
            expandedState: _xiangqiExpanded,
            onToggle: () => setState(() => _xiangqiExpanded = !_xiangqiExpanded),
            preview: _XiangqiFriends(session: xiangqiSession, expanded: false),
            expanded: _XiangqiFriends(session: xiangqiSession, expanded: true),
          ),
          const SizedBox(height: 24.0),
        ],
      ),
    );
  }
}

class const _SignInRow({required final VoidCallback onTap}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListSection(
    hasLeading: true,
    children: [
      ListTile(leading: const Icon(Icons.login), title: Text(context.l10n.signIn), onTap: onTap),
    ],
  );
}

class const _LichessFriends({required final String accountName, required final bool expanded})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineFriendsProvider);
    final following = ref.watch(followingProvider);
    return Column(
      children: [
        online.when(
          data: (friends) {
            final shown = expanded ? friends : friends.take(5).toList();
            return ListSection(
              hasLeading: true,
              header: Text(context.l10n.online),
              children: [
                if (shown.isEmpty)
                  ListTile(dense: true, title: Text(context.l10n.mobileNoFriendsOnline))
                else
                  for (final friend in shown)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle, size: 10),
                      title: Text(friend.user.name),
                    ),
              ],
            );
          },
          loading: () => const ListSection(children: [ListTile(dense: true, title: Text('…'))]),
          error: (error, stackTrace) => ListSection(
            children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
          ),
        ),
        if (expanded)
          following.when(
            data: (users) => ListSection(
              hasLeading: true,
              header: Text(context.l10n.nbFollowing(users.length)),
              children: [
                for (final user in users) ListTile(dense: true, title: Text(user.username)),
              ],
            ),
            loading: () => const ListSection(children: [ListTile(dense: true, title: Text('…'))]),
            error: (error, stackTrace) => ListSection(
              children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
            ),
          ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).push(FriendScreen.buildRoute()),
              child: Text(context.l10n.friends),
            ),
          ),
      ],
    );
  }
}

class const _XiangqiFriends({required final XiangqiSession? session, required final bool expanded})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSession = session;
    if (currentSession == null || currentSession.isGuest) {
      return ListSection(
        hasLeading: true,
        children: [
          ListTile(
            leading: const Icon(Icons.login),
            title: Text(context.l10n.mobileXiangqiSignIn),
            onTap: () =>
                Navigator.of(context, rootNavigator: true).push(XiangqiLoginScreen.buildRoute()),
          ),
        ],
      );
    }

    final friends = ref.watch(xiangqiFriendsProvider((currentSession.name, null)));
    final requests = ref.watch(xiangqiFriendRequestsProvider);
    return Column(
      children: [
        friends.when(
          data: (value) {
            final shown = expanded ? value.friends : value.friends.take(5).toList();
            return ListSection(
              hasLeading: true,
              header: Text(context.l10n.friends),
              children: [
                if (shown.isEmpty)
                  ListTile(dense: true, title: Text(context.l10n.mobileXiangqiFriendsEmpty))
                else
                  for (final friend in shown)
                    ListTile(
                      dense: true,
                      title: Text(friend.player.name),
                      subtitle: friend.player.rating == null
                          ? null
                          : Text('${friend.player.rating}'),
                    ),
              ],
            );
          },
          loading: () => const ListSection(children: [ListTile(dense: true, title: Text('…'))]),
          error: (error, stackTrace) => ListSection(
            children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
          ),
        ),
        if (expanded)
          requests.when(
            data: (value) => ListSection(
              hasLeading: true,
              header: Text(context.l10n.mobileXiangqiFriendRequests),
              children: [
                if (value.isEmpty)
                  ListTile(dense: true, title: Text(context.l10n.mobileXiangqiFriendRequestsEmpty))
                else
                  for (final request in value)
                    ListTile(dense: true, title: Text(request.player.name)),
              ],
            ),
            loading: () => const ListSection(children: [ListTile(dense: true, title: Text('…'))]),
            error: (error, stackTrace) => ListSection(
              children: [ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong))],
            ),
          ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: OutlinedButton(
              onPressed: () => Navigator.of(
                context,
                rootNavigator: true,
              ).push(XiangqiFriendsScreen.buildRoute()),
              child: Text(context.l10n.friends),
            ),
          ),
      ],
    );
  }
}
