import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social_repository.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';
import 'package:material_ui/material_ui.dart';

/// The account's friends on xiangqi.com, and the requests waiting to be answered.
///
/// ## What is measured and what is not
///
/// The two envelopes are measured: the friend list is `{items: [...]}` and the requests are
/// `{friend_requests: [...]}`, and they are **not** the same shape. What an *item* looks like is
/// not: every read this project could make answered with an empty list, because the one account has
/// no friends. So the item is read as the site's one user shape, which is the object it writes
/// everywhere else a user appears — see [XiangqiFriend], which says so at the model.
///
/// The three writes are the ones whose **body shapes** were measured, from the endpoints' own
/// complaints about bodies that were missing them. What none of them has been seen doing is
/// succeeding, for the same reason: there is nobody to point them at.
class const XiangqiFriendsScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiFriendsScreen());

  @override
  ConsumerState<XiangqiFriendsScreen> createState() => _XiangqiFriendsScreenState();
}

class _XiangqiFriendsScreenState() extends ConsumerState<XiangqiFriendsScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **A real account**, for two reasons that agree: the friend list is asked for by username and
    // a guest's own name is not one the server will answer for, and the requests under it are
    // `401` to anybody but a signed-in account — measured both ways on 2026-10-16.
    final session = ref.watch(xiangqiAuthControllerProvider);
    final username = session != null && !session.isGuest ? session.name : null;
    if (username == null) {
      return Scaffold(
        appBar: AppBar(title: AppBarTitleText(context.l10n.friends)),
        body: Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Text(context.l10n.mobileXiangqiSignIn, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final friends = ref.watch(xiangqiFriendsProvider((username, _search.isEmpty ? null : _search)));
    final requests = ref.watch(xiangqiFriendRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.friends}'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: PlatformSearchBar(
              controller: _searchController,
              hintText: context.l10n.search,
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          ListSection(
            hasLeading: true,
            header: Text(context.l10n.mobileXiangqiFriendRequests),
            children: switch (requests) {
              AsyncData(:final value) when value.isEmpty => [
                ListTile(dense: true, title: Text(context.l10n.mobileXiangqiFriendRequestsEmpty)),
              ],
              AsyncData(:final value) => [
                for (final request in value) _RequestRow(request: request, username: username),
              ],
              AsyncError() => [
                ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong)),
              ],
              _ => [const ListTile(dense: true, title: Text('…'))],
            },
          ),
          ListSection(
            hasLeading: true,
            header: Text(context.l10n.friends),
            children: switch (friends) {
              AsyncData(:final value) when value.friends.isEmpty => [
                ListTile(dense: true, title: Text(context.l10n.mobileXiangqiFriendsEmpty)),
              ],
              AsyncData(:final value) => [
                for (final friend in value.friends) _FriendRow(friend: friend, username: username),
              ],
              AsyncError() => [
                ListTile(dense: true, title: Text(context.l10n.mobileSomethingWentWrong)),
              ],
              _ => [const ListTile(dense: true, title: Text('…'))],
            },
          ),
        ],
      ),
    );
  }
}

/// One friend: who it is, and the way to stop being one.
class const _FriendRow({required final XiangqiFriend friend, required final String username})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = friend.player;
    return ListTile(
      title: Text(player.name, overflow: TextOverflow.ellipsis),
      subtitle: player.rating == null ? null : Text('${player.rating}'),
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(XiangqiProfileScreen.buildRoute(player.name)),
      trailing: IconButton(
        tooltip: context.l10n.mobileXiangqiUnfriend,
        icon: const Icon(Icons.person_remove_outlined),
        onPressed: () => _run(
          context,
          ref,
          () => ref.read(xiangqiSocialRepositoryProvider).unfriend(player.name),
          onDone: () => ref.invalidate(xiangqiFriendsProvider((username, null))),
        ),
      ),
    );
  }
}

/// One pending request: who sent it, and the two answers.
class const _RequestRow({
  required final XiangqiFriendRequest request,
  required final String username,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = request.player;
    return ListTile(
      title: Text(player.name, overflow: TextOverflow.ellipsis),
      subtitle: player.rating == null ? null : Text('${player.rating}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.accept,
            icon: const Icon(Icons.check),
            onPressed: () => _answer(context, ref, player, accept: true, username: username),
          ),
          IconButton(
            tooltip: context.l10n.decline,
            icon: const Icon(Icons.close),
            onPressed: () => _answer(context, ref, player, accept: false, username: username),
          ),
        ],
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    XiangqiLivePlayer player, {
    required bool accept,
    required String username,
  }) async {
    // The request is answered by the **sender's id**, which is what the endpoint takes — the name
    // is what the row draws. A seat without an id is a request this app cannot answer, and the
    // button does nothing rather than sending a body the server would refuse.
    final senderId = int.tryParse(player.id);
    if (senderId == null) return;
    await _run(
      context,
      ref,
      () => ref
          .read(xiangqiSocialRepositoryProvider)
          .replyToFriendRequest(senderId: senderId, accept: accept),
      onDone: () => ref.invalidate(xiangqiFriendRequestsProvider),
    );
  }
}

/// Runs [action], says so when it fails, and refreshes when it does not.
///
/// The same three lines for all three of the screen's writes, because they are the same three
/// things: a call, a failure the reader has to be told about, and a list that is now out of date.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required VoidCallback onDone,
}) async {
  try {
    await action();
    onDone();
  } catch (_) {
    if (!context.mounted) return;
    showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
  }
}
