import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social.dart';
import 'package:lichess_mobile/src/model/xiangqi/social/xiangqi_social_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_link.dart';
import 'package:lichess_mobile/src/service/xiangqi_links_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refreshable_empty.dart';
import 'package:material_ui/material_ui.dart';

/// What xiangqi.com has told this account.
///
/// ## Where the list comes from
///
/// The socket, and not REST: `get.notifications` goes out and `get.notifications.success` comes back
/// with a page of them. The one part of notifications that is REST is the preferences, and those are
/// a setting rather than a list — see `xiangqi-com-re/docs/social.md`, which also records that the
/// preferences' own write path answers `500` whatever the body, so there is no screen for it here.
///
/// ## What a row is
///
/// A title, a body, and a link. Most of what this account has ever been sent is a system message
/// with no sender at all — the site's own welcome notes — and the row is built for that: the sender
/// is drawn when there is one and nothing is drawn when there is not, rather than a blank line where
/// a name would be.
class const XiangqiNotificationsScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiNotificationsScreen());

  @override
  ConsumerState<XiangqiNotificationsScreen> createState() => _XiangqiNotificationsScreenState();
}

class _XiangqiNotificationsScreenState() extends ConsumerState<XiangqiNotificationsScreen> {
  /// Whether marking everything read is on its way.
  bool _marking = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(xiangqiAccountGenerationProvider, (_, _) {
      if (mounted) setState(() => _marking = false);
    });
    final notifications = ref.watch(xiangqiNotificationsControllerProvider);

    final identity = ref.watch(xiangqiAccountGenerationProvider);
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => _marking
          ? Future<void>.value()
          : ref.read(xiangqiNotificationsControllerProvider.notifier).refresh(),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: notifications,
        builder: (context, notifications) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.notifications}'),
            actions: [
              DesktopRefreshButton(
                onRefresh: refresh,
                busy: busy || _marking || (notifications.value?.refreshing ?? false),
              ),
              IconButton(
                tooltip: context.l10n.mobileXiangqiNotificationsMarkAllRead,
                icon: const Icon(Icons.done_all),
                // Nothing to mark when there is nothing unread, and nothing to mark while a mark is
                // already on its way.
                onPressed:
                    busy ||
                        _marking ||
                        (notifications.value?.busy ?? false) ||
                        (notifications.value?.items.where((item) => !item.isRead).length ?? 0) == 0
                    ? null
                    : _markAllRead,
              ),
            ],
          ),
          body: notifications.when(
            data: (notifications) =>
                notifications.items.isEmpty &&
                    notifications.nextPage == null &&
                    notifications.refreshError == null &&
                    notifications.moreError == null
                ? XiangqiRefreshableEmpty(
                    onRefresh: refresh,
                    child: const Padding(padding: Styles.bodySectionPadding, child: _Empty()),
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (notifications.items.isEmpty)
                          const Padding(padding: Styles.bodySectionPadding, child: _Empty()),
                        if (notifications.items.isNotEmpty)
                          ListSection(
                            hasLeading: true,
                            children: [
                              for (final notification in notifications.items)
                                _NotificationRow(notification: notification),
                            ],
                          ),
                        if (notifications.refreshError != null)
                          XiangqiRetryTile(onRetry: busy ? null : () => unawaited(refresh())),
                        XiangqiPaginationFooter(
                          hasMore: notifications.nextPage != null,
                          loading: notifications.loadingMore,
                          failed: notifications.moreError != null,
                          onMore: notifications.refreshing || _marking
                              ? null
                              : () => unawaited(
                                  ref
                                      .read(xiangqiNotificationsControllerProvider.notifier)
                                      .getMore(),
                                ),
                          onRetry: notifications.refreshing || _marking
                              ? null
                              : () => unawaited(
                                  ref
                                      .read(xiangqiNotificationsControllerProvider.notifier)
                                      .getMore(),
                                ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            error: (error, stackTrace) => Center(
              child: Padding(
                padding: Styles.bodySectionPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(switch (error) {
                      XiangqiSocialException(reason: .noSession) =>
                        context.l10n.mobileXiangqiSignIn,
                      XiangqiSocialException(reason: .offline) =>
                        context.l10n.mobileXiangqiReviewOffline,
                      _ => context.l10n.mobileSomethingWentWrong,
                    }, textAlign: TextAlign.center),
                    const SizedBox(height: 16.0),
                    FilledButton(onPressed: refresh, child: Text(context.l10n.retry)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Marks every notification read, and redraws the list once the server has said so.
  Future<void> _markAllRead() async {
    if (_marking) return;
    final generation = ref.read(xiangqiAccountGenerationProvider);
    setState(() => _marking = true);
    try {
      final marked = await ref.read(xiangqiNotificationsControllerProvider.notifier).markAllRead();
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      if (!marked) {
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } catch (_) {
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
    } finally {
      if (mounted && generation == ref.read(xiangqiAccountGenerationProvider)) {
        setState(() => _marking = false);
      }
    }
  }
}

/// One notification: what it says, when it came, and the way to what it points at.
class const _NotificationRow({required final XiangqiNotification notification})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = notification.url;
    final uri = url == null ? null : xiangqiContentUri(url);
    final links = ref.read(xiangqiLinksServiceProvider);
    final account = ref.watch(xiangqiAccountGenerationProvider);
    return ListTile(
      // The unread mark is a dot rather than a colour on the whole row: a list where every other
      // row is tinted reads as a list of two kinds of thing, and these are one kind in two states.
      leading: Icon(
        notification.isRead ? Icons.circle_outlined : Icons.circle,
        size: notification.isRead ? 8 : 10,
        color: notification.isRead ? textShade(context, 0.3) : ColorScheme.of(context).primary,
      ),
      title: Text(notification.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (notification.senderName != null) notification.senderName!,
          notification.message,
        ].join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: notification.createdAt == null
          ? null
          : Text(
              _date(notification.createdAt!),
              style: TextStyle(fontSize: 12, color: textShade(context, 0.5)),
            ),
      // A notification with nowhere to go is a row that says so by not being tappable, rather than
      // one that opens something and then does nothing.
      onTap: uri == null
          ? null
          : () =>
                links.openContentLink(context, uri.toString(), expectedAccountGeneration: account),
    );
  }

  /// [instant] as a date, without a time.
  String _date(DateTime instant) =>
      '${instant.year}-${instant.month.toString().padLeft(2, '0')}-'
      '${instant.day.toString().padLeft(2, '0')}';
}

/// What the list says when there is nothing in it.
class const _Empty() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.mobileXiangqiNotificationsEmpty, textAlign: TextAlign.center);
  }
}
