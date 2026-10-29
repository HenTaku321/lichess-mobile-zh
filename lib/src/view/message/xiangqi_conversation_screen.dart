// The conversation screen for a xiangqi.com chat.
//
// A separate screen from the lichess `ConversationScreen` rather than one screen with two branches,
// because almost nothing underneath is shared: the two conversations are different protocols with
// different messages, different paging and different read state. What they do share is the shape the
// user sees, so this is built to the lichess screen's measurements — the same app bar with an avatar
// and a name, the same right/left bubbles on the same 0.85 width factor, the same day separators, the
// same input row — so that a xiangqi chat and a chess chat read as two screens of one app.
//
// Two things the lichess screen has are deliberately absent, because there is nothing honest to put
// there. There is no delete action: no capture shows how xiangqi.com deletes a conversation, and a
// confident-looking button that does nothing would be worse than none. There is no tap-through to a
// profile: a xiangqi.com user has no lichess profile to open. There is also no "read"/typing
// indicator, because xiangqi.com's typing frames were never captured doing anything this app can
// trust.
//
// The avatar is initials, not a photo: xiangqi.com does send a `profile_image` URL, but the app's
// `UserAvatar` only fetches a remote image for a lichess flair, and it is a shared widget that this
// wave must not change. The initials are the honest fallback, and the same one the chat list uses.

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class const XiangqiConversationScreen({
  required final String chatId,
  required final int peerId,
  required final LightUser peer,
  super.key,
}) extends ConsumerWidget {
  static Route<dynamic> buildRoute({
    required String chatId,
    required int peerId,
    required LightUser peer,
  }) {
    return buildScreenRoute(
      screen: XiangqiConversationScreen(chatId: chatId, peerId: peerId, peer: peer),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = (chatId: chatId, peerId: peerId, peer: peer);
    return XiangqiRefreshScope(
      identity: (conversation, ref.watch(xiangqiAccountGenerationProvider)),
      onRefresh: () => ref.refresh(xiangqiConversationControllerProvider(conversation).future),
      builder: (context, refresh, busy) => PlatformScaffold(
        appBar: PlatformAppBar(
          titleSpacing: 0,
          actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          title: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(peer, radius: 16),
            title: UserFullNameWidget(user: peer, showFlair: false),
          ),
        ),
        body: _Body(conversation: conversation, onRefresh: refresh, busy: busy),
      ),
    );
  }
}

class const _Body({
  required final XiangqiConversationKey conversation,
  required final XiangqiRefresh onRefresh,
  required final bool busy,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(xiangqiConversationControllerProvider(conversation));

    return XiangqiRetainedData(
      identity: (conversation, ref.watch(xiangqiAccountGenerationProvider)),
      value: stateAsync,
      builder: (context, stateAsync) {
        switch (stateAsync) {
          case AsyncData(:final value):
            final items = _buildItems(value.convo.messages, conversation.peerId);
            return Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView.builder(
                      // The bottom padding the input row already provides.
                      padding: MediaQuery.paddingOf(context).copyWith(bottom: 0),
                      // Newest at the bottom: the server hands the page over newest-first and the list
                      // is drawn the way a chat reads.
                      reverse: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return switch (item) {
                          _DateItem(:final date) => _DateBubble(date: date),
                          _MessageItem(
                            :final message,
                            :final isMe,
                            :final groupLength,
                            :final groupIndex,
                          ) =>
                            _MessageBubble(
                              message: message,
                              isMe: isMe,
                              groupLength: groupLength,
                              groupIndex: groupIndex,
                            ),
                        };
                      },
                    ),
                  ),
                ),
                _MessageInput(
                  key: ValueKey(ref.watch(xiangqiAccountGenerationProvider)),
                  conversation: conversation,
                ),
              ],
            );
          case AsyncError(:final error, :final stackTrace):
            debugPrint(
              'Error loading xiangqi conversation ${conversation.chatId}: $error\n$stackTrace',
            );
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.mobileSomethingWentWrong),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: busy ? null : onRefresh, child: Text(context.l10n.retry)),
                ],
              ),
            );
          case _:
            return const Center(child: CircularProgressIndicator.adaptive());
        }
      },
    );
  }

  /// The messages, with a day separator before each day's run of them.
  ///
  /// Which side a message sits on is decided against the peer: a xiangqi conversation has exactly
  /// two participants and a message's sender is one of them, so "not the peer" is "this device".
  /// The peer's id is the only participant id this screen is guaranteed to know — the app-level
  /// identity in the state may be a lichess account, whose id a xiangqi `sender_id` can never equal.
  List<_DisplayItem> _buildItems(IList<Message> messages, int peerId) {
    final peerUserId = xiangqiUserId(peerId);
    final items = <_DisplayItem>[];
    DateTime? currentDay;
    final dayMessages = <Message>[];

    void flushDay() {
      var start = 0;
      while (start < dayMessages.length) {
        var end = start + 1;
        while (end < dayMessages.length && dayMessages[end].userId == dayMessages[start].userId) {
          end++;
        }
        for (var index = start; index < end; index++) {
          final message = dayMessages[index];
          items.add(
            _MessageItem(
              message,
              isMe: message.userId != peerUserId,
              groupLength: end - start,
              groupIndex: index - start,
            ),
          );
        }
        start = end;
      }
      items.add(_DateItem(currentDay!));
      dayMessages.clear();
    }

    for (final message in messages) {
      final day = DateTime(message.date.year, message.date.month, message.date.day);
      if (currentDay != null && currentDay != day) {
        flushDay();
      }
      currentDay = day;
      dayMessages.add(message);
    }
    if (dayMessages.isNotEmpty) {
      flushDay();
    }
    return items;
  }
}

sealed class _DisplayItem();

class _DateItem(final DateTime date) extends _DisplayItem;

class _MessageItem(
  final Message message, {
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
}) extends _DisplayItem;

/// The day label, built to the lichess conversation's own: today, yesterday, or a short date.
class const _DateBubble({required final DateTime date}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final aDate = DateTime(date.year, date.month, date.day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            aDate.isAtSameMomentAs(today)
                ? context.l10n.today
                : aDate.isAtSameMomentAs(yesterday)
                ? context.l10n.yesterday
                : DateFormat.yMMMd().format(date),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// One message, drawn with the lichess conversation's bubble colours and side.
class const _MessageBubble({
  required final Message message,
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final textColor = isMe ? colorScheme.onSecondaryContainer : colorScheme.onSurface;
    final time = DateFormat.Hm().format(message.date);
    final timeStyle = TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6));
    final grouped = groupLength > 1;
    final first = groupIndex == 0;
    final last = groupIndex == groupLength - 1;
    const radius = Radius.circular(16);
    const inGroupRadius = Radius.circular(4);

    return ChatBubbleContextMenu(
      message: message.text,
      child: FractionallySizedBox(
        alignment: isMe ? .centerRight : .centerLeft,
        widthFactor: 0.85,
        child: Align(
          alignment: isMe ? .centerRight : .centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              bottom: !grouped || first ? 8 : 2,
              top: !grouped || last ? 8 : 2,
              left: 8,
              right: 8,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: isMe ? colorScheme.secondaryContainer : colorScheme.surfaceContainer,
              borderRadius: BorderRadius.only(
                topLeft: !isMe && grouped && !last ? inGroupRadius : radius,
                topRight: isMe && grouped && !last ? inGroupRadius : radius,
                bottomLeft: !isMe && grouped && !first ? inGroupRadius : radius,
                bottomRight: isMe && grouped && !first ? inGroupRadius : radius,
              ),
            ),
            child: Stack(
              children: [
                RichLinkText(
                  text: message.text,
                  style: TextStyle(color: textColor),
                  linkStyle: Styles.linkStyle,
                  onOpen: (link) async {
                    final uri = Uri.tryParse(link.url);
                    if (uri != null && const {'https', 'http', 'mailto'}.contains(uri.scheme)) {
                      await launchUrl(uri);
                    }
                  },
                  // Reserve the same last-line timestamp space as the Lichess conversation.
                  trailing: WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: Opacity(
                      opacity: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(time, style: timeStyle),
                      ),
                    ),
                  ),
                ),
                Positioned(right: 0, bottom: 0, child: Text(time, style: timeStyle)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _MessageInput({required final XiangqiConversationKey conversation, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState() extends ConsumerState<_MessageInput> {
  final controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final original = controller.text;
    final text = original.trim();
    if (text.isEmpty || _sending) return;
    final generation = ref.read(xiangqiAccountGenerationProvider);
    setState(() => _sending = true);
    try {
      final dispatched = await ref
          .read(xiangqiConversationControllerProvider(widget.conversation).notifier)
          .sendMessage(text);
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      if (dispatched) {
        if (controller.text == original) controller.clear();
      } else {
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } on Object {
      if (mounted && generation == ref.read(xiangqiAccountGenerationProvider)) {
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: TextField(
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
            suffixIcon: IconButton(
              tooltip: context.l10n.send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator.adaptive(),
                    )
                  : const Icon(Icons.send),
              onPressed: _sending ? null : send,
            ),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20.0))),
          ),
          controller: controller,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 4,
          enableSuggestions: true,
          onSubmitted: (_) => send(),
        ),
      ),
    );
  }
}
