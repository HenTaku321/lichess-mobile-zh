import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/message/conversation_controller.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/service/app_links_service.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/chat_presentation.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

sealed class DisplayItem();

class DateItem(final DateTime date) extends DisplayItem;

class MessageItem(
  final Message message, {
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
}) extends DisplayItem;

class GetMoreItem() extends DisplayItem;

class ContactTypingItem() extends DisplayItem;

class const ConversationScreen({super.key, required final LightUser user})
    extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute({required LightUser user}) {
    return buildScreenRoute(screen: ConversationScreen(user: user));
  }

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState() extends ConsumerState<ConversationScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route is PageRoute) {
      rootNavPageRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootNavPageRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPop() {
    ref.invalidate(unreadMessagesProvider);
    super.didPop();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        titleSpacing: 0,
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(widget.user, radius: 16),
          title: UserFullNameWidget(user: widget.user, showFlair: false),
          subtitle: Text(widget.user.isOnline == true ? context.l10n.online : context.l10n.offline),
          onTap: () {
            Navigator.push(context, UserOrProfileScreen.buildRoute(widget.user))
            // invalidate to refresh potential blocking status change
            .then((_) {
              if (context.mounted) {
                ref.invalidate(conversationControllerProvider(widget.user.id));
              }
            });
          },
        ),
        actions: [
          if (widget.user.id.value != 'lichess')
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.l10n.mobileDeleteConversation,
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => YesNoDialog(
                    title: Text(context.l10n.mobileAreYouSure),
                    content: Text(context.l10n.mobileDeleteConversationConfirm),
                    onYes: () => Navigator.of(context).pop(true),
                    onNo: () => Navigator.of(context).pop(false),
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await ref
                      .read(conversationControllerProvider(widget.user.id).notifier)
                      .deleteThread();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
        ],
      ),
      body: _Body(user: widget.user),
    );
  }
}

class const _Body({required final LightUser user}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageStateAsync = ref.watch(conversationControllerProvider(user.id));

    switch (messageStateAsync) {
      case AsyncData(:final value):
        final items = buildDisplayItems(value);
        final occurrences = <Message, int>{};
        final days = <DateTime, int>{};
        return Column(
          children: [
            Expanded(
              child: ChatMessageList(
                itemCount: items.length,
                itemKeys: [
                  for (final item in items)
                    switch (item) {
                      DateItem(:final date) => (
                        'day',
                        date,
                        days.update(date, (count) => count + 1, ifAbsent: () => 0),
                      ),
                      MessageItem(:final message) => (
                        'message',
                        message,
                        occurrences.update(message, (count) => count + 1, ifAbsent: () => 0),
                      ),
                      GetMoreItem() => 'history-footer',
                      ContactTypingItem() => 'typing',
                    },
                ].toIList(),
                itemBuilder: (context, index) {
                  final item = items[index];
                  switch (item) {
                    case DateItem(:final date):
                      return ChatDaySeparator(date: date);
                    case MessageItem(:final message, :final isMe):
                      return _MessageBubble(
                        message: message,
                        isMe: isMe,
                        groupLength: item.groupLength,
                        groupIndex: item.groupIndex,
                      );
                    case GetMoreItem():
                      return Center(
                        child: TextButton(
                          onPressed: () =>
                              ref.read(conversationControllerProvider(user.id).notifier).getMore(),
                          child: Text(context.l10n.mobileLoadMore),
                        ),
                      );
                    case ContactTypingItem():
                      return _ContactTyping(user: user);
                  }
                },
              ),
            ),
            _MessageInput(user: user, state: value),
          ],
        );
      case AsyncError(error: final e, stackTrace: final st):
        debugPrint('Error loading messages for ${user.id}: $e\n$st');
        return Center(child: Text('Error: $e'));
      case _:
        return const Center(child: CircularProgressIndicator());
    }
  }

  List<List<Message>> _groupContiguousByUser(List<Message> messages) {
    final grouped = <List<Message>>[];
    if (messages.isEmpty) return grouped;

    var currentGroup = <Message>[];
    for (final message in messages) {
      if (currentGroup.isEmpty || currentGroup.last.userId == message.userId) {
        currentGroup.add(message);
      } else {
        grouped.add(currentGroup);
        currentGroup = [message];
      }
    }
    if (currentGroup.isNotEmpty) {
      grouped.add(currentGroup);
    }
    return grouped;
  }

  List<DisplayItem> buildDisplayItems(ConversationState state) {
    final messages = state.convo.messages;
    final items = <DisplayItem>[];
    DateTime? currentDate;
    final List<Message> dayMessages = [];

    items.add(ContactTypingItem());

    void processDayMessages() {
      final byUser = _groupContiguousByUser(dayMessages);
      for (final group in byUser) {
        for (var i = 0; i < group.length; i++) {
          final m = group[i];
          items.add(
            MessageItem(m, isMe: m.userId == state.me.id, groupLength: group.length, groupIndex: i),
          );
        }
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      final messageDate = DateTime(message.date.year, message.date.month, message.date.day);
      final isNewDay = currentDate == null || currentDate != messageDate;
      final isLast = i == messages.length - 1;

      if (isNewDay && dayMessages.isNotEmpty) {
        processDayMessages();
        items.add(DateItem(currentDate!));
        dayMessages.clear();
      }

      currentDate = messageDate;
      dayMessages.add(message);

      if (isLast) {
        processDayMessages();
        items.add(DateItem(currentDate));
      }
    }

    if (state.canGetMoreSince != null) {
      items.add(GetMoreItem());
    }

    return items;
  }
}

class const _ContactTyping({required final LightUser user}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTyping = ref.watch(
      conversationControllerProvider(user.id).select((state) => state.value?.contactTyping == true),
    );
    return ChatTypingStatus(text: isTyping ? '${user.name} is typing...' : null);
  }
}

class const _MessageBubble({
  required final Message message,
  required final bool isMe,
  required final int groupLength,
  required final int groupIndex,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          linkifiers: AppLinksService.kLichessLinkifiers,
          onLinkOpen: (link) => ref.read(appLinksServiceProvider).onLinkifyOpen(context, link),
        ),
      ),
    );
  }
}

class const _MessageInput({required final LightUser user, required final ConversationState state})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState() extends ConsumerState<_MessageInput> {
  final controller = TextEditingController();

  bool get isBlocked => widget.state.isBlocked ?? false;

  bool get isBot => widget.state.isBot;

  bool get canPost => widget.state.convo.postable;

  bool get readOnly => isBlocked || isBot || !canPost;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleTypingStatus);
  }

  void _handleTypingStatus() {
    if (controller.text.isNotEmpty && mounted) {
      ref.read(conversationControllerProvider(widget.user.id).notifier).setTyping(widget.user.id);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleTypingStatus);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sendButton = IconButton(
      icon: Icon(readOnly ? Icons.block : Icons.send),
      onPressed: () {
        final text = controller.text.trim();
        if (text.isNotEmpty) {
          ref
              .read(conversationControllerProvider(widget.user.id).notifier)
              .sendMessage(widget.user.id, text);
          controller.clear();
        }
      },
    );

    return ChatComposerInput(
      appearance: .conversation,
      sendButton: sendButton,
      hintText: isBlocked
          ? 'This conversation is blocked.'
          : isBot
          ? 'Bot accounts cannot send nor receive messages.'
          : !canPost
          ? "${widget.user.name} doesn't accept new messages."
          : null,
      controller: controller,
      readOnly: readOnly,
    );
  }
}
