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
// lichess profile. A visible username opens the xiangqi profile instead; a hidden name is not a
// profile identity. There is also no "read"/typing indicator, because xiangqi.com's typing frames
// were never captured doing anything this app can trust.
//
// The avatar is initials, not a photo: xiangqi.com does send a `profile_image` URL, but the app's
// `UserAvatar` only fetches a remote image for a lichess flair, and it is a shared widget that this
// wave must not change. The initials are the honest fallback, and the same one the chat list uses.

import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_link.dart';
import 'package:lichess_mobile/src/service/xiangqi_links_service.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/widgets/chat_presentation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

class const XiangqiConversationScreen({
  required final String chatId,
  required final int peerId,
  required final LightUser peer,
  final bool peerProfileAvailable = false,
  super.key,
}) extends ConsumerWidget {
  static Route<dynamic> buildRoute({
    required String chatId,
    required int peerId,
    required LightUser peer,
    bool peerProfileAvailable = false,
  }) {
    return buildScreenRoute(
      screen: XiangqiConversationScreen(
        chatId: chatId,
        peerId: peerId,
        peer: peer,
        peerProfileAvailable: peerProfileAvailable,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = (chatId: chatId, peerId: peerId, peer: peer);
    final account = ref.watch(xiangqiAccountGenerationProvider);
    final links = ref.read(xiangqiLinksServiceProvider);
    return XiangqiRefreshScope(
      identity: (conversation, account),
      onRefresh: () =>
          ref.read(xiangqiConversationControllerProvider(conversation).notifier).refresh(),
      builder: (context, refresh, busy) => PlatformScaffold(
        appBar: PlatformAppBar(
          titleSpacing: 0,
          actions: [DesktopRefreshButton(onRefresh: refresh, busy: busy)],
          title: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(peer, radius: 16),
            title: UserFullNameWidget(user: peer, showFlair: false),
            onTap: peerProfileAvailable && isXiangqiProfileName(peer.name)
                ? () => links.openProfile(context, peer.name, expectedAccountGeneration: account)
                : null,
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
            final items = _buildItems(value.convo.messages, value.selfId);
            final messageOccurrences = <Message, int>{};
            final dayOccurrences = <DateTime, int>{};
            return Column(
              children: [
                Expanded(
                  child: ChatMessageList(
                    itemCount: items.length + 1,
                    itemKeys: [
                      for (final item in items)
                        switch (item) {
                          _DateItem(:final date) => (
                            'day',
                            date,
                            dayOccurrences.update(date, (count) => count + 1, ifAbsent: () => 0),
                          ),
                          _MessageItem(:final message) => (
                            'message',
                            message,
                            messageOccurrences.update(
                              message,
                              (count) => count + 1,
                              ifAbsent: () => 0,
                            ),
                          ),
                          _StatusItem() => 'status',
                        },
                      'history-footer',
                    ].toIList(),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (value.pagination.refreshError != null)
                              XiangqiRetryTile(
                                onRetry: busy
                                    ? null
                                    : () => unawaited(
                                        ref
                                            .read(
                                              xiangqiConversationControllerProvider(conversation)
                                                  .notifier,
                                            )
                                            .retryRefresh(),
                                      ),
                              ),
                            XiangqiPaginationFooter(
                              hasMore: value.pagination.nextPage != null,
                              loading: value.pagination.loadingMore,
                              failed: value.pagination.moreError != null,
                              onMore: busy
                                  ? null
                                  : () => unawaited(
                                      ref
                                          .read(
                                            xiangqiConversationControllerProvider(conversation)
                                                .notifier,
                                          )
                                          .getMore(),
                                    ),
                              onRetry: busy
                                  ? null
                                  : () => unawaited(
                                      ref
                                          .read(
                                            xiangqiConversationControllerProvider(conversation)
                                                .notifier,
                                          )
                                          .getMore(),
                                    ),
                            ),
                          ],
                        );
                      }
                      final item = items[index];
                      return switch (item) {
                        _StatusItem() => const ChatTypingStatus(),
                        _DateItem(:final date) => ChatDaySeparator(date: date),
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
                _MessageInput(
                  key: ValueKey((conversation, ref.watch(xiangqiAccountGenerationProvider))),
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
  /// Bubble alignment uses the actual Xiangqi sender, not the app's scalar Lichess identity and
  /// never the assumption that every unknown sender must be this device.
  List<_DisplayItem> _buildItems(IList<Message> messages, UserId selfId) {
    final items = <_DisplayItem>[_StatusItem()];
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
              isMe: message.userId == selfId,
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

class _StatusItem() extends _DisplayItem;

class _DateItem(final DateTime date) extends _DisplayItem;

class _MessageItem(
  final Message message, {
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
}) extends _DisplayItem;

/// One message, drawn with the lichess conversation's bubble colours and side.
class const _MessageBubble({
  required final Message message,
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.read(xiangqiLinksServiceProvider);
    final account = ref.watch(xiangqiAccountGenerationProvider);
    return ChatBubbleContextMenu(
      message: message.text,
      child: ChatBubbleSurface(
        appearance: .conversation,
        isMine: isMe,
        groupLength: groupLength,
        groupIndex: groupIndex,
        child: ChatMessageContent(
          text: message.text,
          time: DateFormat.Hm().format(message.date),
          onLinkOpen: (link) =>
              links.onLinkifyOpen(context, link, expectedAccountGeneration: account),
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
    return ChatComposerInput(
      appearance: .conversation,
      controller: controller,
      onSubmitted: (_) => send(),
      sendButton: IconButton(
        tooltip: context.l10n.send,
        icon: _sending
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator.adaptive())
            : const Icon(Icons.send),
        onPressed: _sending ? null : send,
      ),
    );
  }
}
