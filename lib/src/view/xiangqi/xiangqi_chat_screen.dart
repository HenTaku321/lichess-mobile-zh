import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// xiangqi.com's chat: the public rooms, and the clubs the account is in.
///
/// The two are one screen because they are one thing to a reader — somewhere to talk — and the
/// three public rooms are the whole of what this app can offer without an account that has been
/// around long enough to join a club: a club needs fourteen days and fourteen games, which is
/// written down in `xiangqi-com-re/docs/chat.md`. So the club section is an empty state that says
/// so, and the rooms are what there is to open.
///
/// Private messages are not here. They are the account's inbox, which this app already has — see
/// `xiangqi_inbox_repository.dart` — and a second door onto the same conversation would be a second
/// place for it to be out of date.
class const XiangqiChatScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiChatScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(xiangqiChatRoomsProvider);

    final identity = ref.watch(xiangqiAccountGenerationProvider);
    return XiangqiRefreshScope(
      identity: identity,
      onRefresh: () => ref.refresh(xiangqiChatRoomsProvider.future),
      builder: (context, refresh, busy) => XiangqiRetainedData(
        identity: identity,
        value: rooms,
        builder: (context, rooms) => Scaffold(
          appBar: AppBar(
            title: AppBarTitleText(
              '${context.l10n.mobileXiangqi} · ${context.l10n.mobileXiangqiChat}',
            ),
            actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          ),
          body: rooms.when(
            data: (rooms) => RefreshIndicator.adaptive(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ListSection(
                    hasLeading: true,
                    header: Text(context.l10n.mobileXiangqiChatRooms),
                    children: [for (final room in rooms) _RoomRow(room: room)],
                  ),
                  ListSection(
                    hasLeading: true,
                    header: Text(context.l10n.mobileXiangqiChatClubs),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(context.l10n.mobileXiangqiChatNoClubs),
                        subtitle: Text(context.l10n.mobileXiangqiChatClubsSubtitle),
                      ),
                    ],
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
                    Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
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
}

/// One public room.
class const _RoomRow({required final XiangqiChatRoom room}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.forum_outlined),
      title: Text(room.name),
      subtitle: room.description == null ? null : Text(room.description!),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const CupertinoListTileChevron()
          : null,
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        XiangqiChatRoomScreen.buildRoute(
          roomKey: (kind: XiangqiChatKind.lobby, room: room.name),
          title: room.name,
        ),
      ),
    );
  }
}

/// One room's chat: what has been said, and the field to say something in.
///
/// The list is drawn bottom-up — a chat is read from its newest message — and the model hands the
/// messages over oldest first, so the two are one reversal apart. That reversal is why the "older
/// messages" row sits at the far end of the list: scrolling up is scrolling back in time, and the
/// next page is what is behind the oldest message on screen.
class const XiangqiChatRoomScreen({
  /// Which room this is, and which kind of chat it is: a public room, or a game's own.
  required final XiangqiChatRoomKey roomKey,
  required final String title,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute({required XiangqiChatRoomKey roomKey, required String title}) =>
      buildScreenRoute(
        screen: XiangqiChatRoomScreen(roomKey: roomKey, title: title),
      );

  @override
  ConsumerState<XiangqiChatRoomScreen> createState() => _XiangqiChatRoomScreenState();
}

class _XiangqiChatRoomScreenState() extends ConsumerState<XiangqiChatRoomScreen> {
  bool _sending = false;
  String? _submittedText;
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _submittedText = text;
      _input.clear();
    });
    try {
      final submitted = await ref
          .read(xiangqiChatControllerProvider(widget.roomKey).notifier)
          .send(text);
      if (!mounted) return;
      if (!submitted) {
        _restoreDraft(text);
        showSnackBar(context, context.l10n.mobileXiangqiChatOffline, type: SnackBarType.error);
      }
    } on Object {
      if (mounted) {
        _restoreDraft(text);
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _restoreDraft(String text) {
    if (_input.text.isEmpty) _input.text = text;
    _submittedText = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(xiangqiChatControllerProvider(widget.roomKey).select((s) => s.error), (
      before,
      after,
    ) {
      if (after == XiangqiChatError.send &&
          after != before &&
          _input.text.isEmpty &&
          _submittedText != null) {
        _input.text = _submittedText!;
        _submittedText = null;
      }
    });
    final state = ref.watch(xiangqiChatControllerProvider(widget.roomKey));
    final controller = ref.read(xiangqiChatControllerProvider(widget.roomKey).notifier);
    final myId = int.tryParse(ref.watch(xiangqiAuthControllerProvider)?.userId ?? '');

    return Scaffold(
      appBar: AppBar(title: AppBarTitleText(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _Messages(
                state: state,
                myId: myId,
                onLoadMore: controller.loadMore,
                onRetry: controller.retry,
              ),
            ),
            if (state.messages.isNotEmpty && state.error != null)
              TextButton(onPressed: controller.retry, child: Text(context.l10n.retry)),
            _Composer(
              controller: _input,
              enabled: state.isConnected && !_sending,
              onSend: _send,
              hint: context.l10n.mobileXiangqiChatSend,
            ),
          ],
        ),
      ),
    );
  }
}

/// What has been said in the room.
class const _Messages({
  required final XiangqiChatState state,
  required final int? myId,
  required final VoidCallback onLoadMore,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: Styles.bodySectionPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error == XiangqiChatError.offline
                    ? context.l10n.mobileXiangqiChatOffline
                    : context.l10n.mobileSomethingWentWrong,
                textAlign: TextAlign.center,
              ),
              FilledButton(onPressed: onRetry, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      );
    }
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.isEmpty) {
      return Center(
        child: Padding(
          padding: Styles.bodySectionPadding,
          child: Text(context.l10n.mobileXiangqiChatEmpty, textAlign: TextAlign.center),
        ),
      );
    }

    final messages = state.messages;
    return ListView.builder(
      // Bottom-up: the newest message is the one the reader is looking at, and a message that
      // arrives does not push the rest of the room up the screen.
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: state.isLoadingMore
                  ? const CircularProgressIndicator.adaptive()
                  : TextButton(
                      onPressed: onLoadMore,
                      child: Text(context.l10n.mobileXiangqiChatLoadOlder),
                    ),
            ),
          );
        }
        final message = messages[messages.length - 1 - index];
        return _Bubble(message: message, isMine: myId != null && message.senderId == myId);
      },
    );
  }
}

/// One message: who said it, what they said, and when.
class const _Bubble({required final XiangqiChatMessage message, required final bool isMine})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final textColor = isMine ? scheme.onSecondary : scheme.onSurface;
    return ChatBubbleContextMenu(
      message: message.message,
      child: FractionallySizedBox(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        widthFactor: 0.9,
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              color: isMine ? scheme.secondary : scheme.surfaceContainerHigh,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine && message.senderName != null)
                  Text(
                    message.senderName!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                  ),
                RichLinkText(
                  text: message.message,
                  style: TextStyle(color: textColor),
                  linkStyle: Styles.linkStyle,
                  onOpen: (link) async {
                    final uri = Uri.tryParse(link.url);
                    if (uri != null && const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The field a message is written in.
class const _Composer({
  required final TextEditingController controller,
  required final bool enabled,
  required final Future<void> Function() onSend,
  required final String hint,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.send,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
        minLines: 1,
        maxLines: 4,
        onSubmitted: (_) => onSend(),
        decoration: InputDecoration(
          hintText: enabled ? hint : context.l10n.mobileXiangqiChatOffline,
          contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20.0))),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => IconButton(
              onPressed: enabled && value.text.trim().isNotEmpty ? () => onSend() : null,
              icon: const Icon(Icons.send),
              tooltip: hint,
            ),
          ),
        ),
      ),
    );
  }
}
