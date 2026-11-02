import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/chat/chat.dart';
import 'package:lichess_mobile/src/model/chat/chat_providers.dart';
import 'package:lichess_mobile/src/service/app_links_service.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/chat_presentation.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

class const ChatBottomBarButton({
  required final ChatOptions options,
  final bool showLabel = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatUnread = ref.watch(chatUnreadProvider(options));

    return BottomBarButton(
      label: context.l10n.chatRoom,
      showLabel: showLabel,
      onTap: () => Navigator.of(context).push(ChatScreen.buildRoute(options: options)),
      icon: Icons.chat_bubble_outline,
      badgeLabel: switch (chatUnread) {
        AsyncData(:final value) =>
          value > 0
              ? value < 10
                    ? value.toString()
                    : '9+'
              : null,
        _ => null,
      },
    );
  }
}

class const ChatScreen({required final ChatOptions options}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute({required ChatOptions options}) {
    return buildScreenRoute(screen: ChatScreen(options: options));
  }

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ChatScreenState();
}

class _ChatScreenState() extends ConsumerState<ChatScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route is PageRoute) {
      rootNavPageRouteObserver.subscribe(this, route);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatNotifierProvider(widget.options)).onFocusRegained();
    });
  }

  @override
  void dispose() {
    rootNavPageRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPop() {
    ref.read(chatNotifierProvider(widget.options)).markMessagesAsRead();
    super.didPop();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider);
    final chatState = ref.watch(chatProvider(widget.options));
    return FocusDetector(
      onFocusRegained: () {
        if (context.mounted) {
          ref.read(chatNotifierProvider(widget.options)).onFocusRegained();
        }
      },
      onForegroundLost: () {
        if (context.mounted) {
          ref.read(chatNotifierProvider(widget.options)).onForegroundLost();
        }
      },
      child: switch (chatState) {
        AsyncValue(:final value?, hasValue: true) => Scaffold(
          appBar: AppBar(
            title: widget.options is TvChatOptions
                ? Text(context.l10n.spectatorRoom)
                : widget.options.isPublic
                ? Text(context.l10n.chatRoom)
                : widget.options.opponent == null
                ? Text(context.l10n.chatRoom)
                : UserFullNameWidget(user: widget.options.opponent),
            centerTitle: true,
          ),
          body: Column(
            children: [
              // Display error if there is one, but still show the messages if they are available
              if (chatState.hasError)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      chatState.error.toString(),
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              Expanded(
                child: ChatMessageList(
                  itemCount: value.messages.length,
                  itemBuilder: (context, index) {
                    final message = value.messages[value.messages.length - index - 1];
                    return (message.username == 'lichess')
                        ? _MessageAction(message: message.message)
                        : (message.username == authUser?.user.name)
                        ? _MessageBubble(options: widget.options, you: true, message: message)
                        : _MessageBubble(
                            options: widget.options,
                            you: false,
                            message: message,
                            showUsername: widget.options.isPublic,
                          );
                  },
                ),
              ),
              if (widget.options.writeable) _ChatBottomBar(options: widget.options),
            ],
          ),
        ),
        AsyncValue(:final error?) => Scaffold(body: Center(child: Text(error.toString()))),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator.adaptive())),
      },
    );
  }
}

class const _MessageBubble({
  required final ChatOptions options,
  required final bool you,
  required final ChatMessage message,
  final bool showUsername = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChatBubbleContextMenu(
      message: message.message,
      actions: [
        if (you == false && message.user != null)
          BottomSheetContextMenuAction(
            onPressed: () async {
              final result = await showAdaptiveDialog<bool>(
                context: context,
                builder: (context) => YesNoDialog(
                  content: Text(context.l10n.reportXToModerators('"${message.message}"')),
                  onYes: () {
                    return Navigator.of(context).pop(true);
                  },
                  onNo: () => Navigator.of(context).pop(false),
                ),
              );
              if (result == true) {
                ref.read(chatNotifierProvider(options)).reportMessage(message);
              }
            },
            icon: Icons.report_problem_outlined,
            child: const Text('Report'),
          ),
      ],
      child: ChatBubbleSurface(
        appearance: .room,
        isMine: you,
        child: ChatMessageContent(
          text: message.message,
          linkifiers: AppLinksService.kLichessLinkifiers,
          onLinkOpen: (link) => ref.read(appLinksServiceProvider).onLinkifyOpen(context, link),
          sender: !showUsername || message.user == null
              ? null
              : UserFullNameWidget(
                  user: message.user,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  onTap: () =>
                      Navigator.of(context).push(UserOrProfileScreen.buildRoute(message.user!)),
                ),
        ),
      ),
    );
  }
}

class const _MessageAction({required final String message}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.8,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
      ),
    );
  }
}

class const _ChatBottomBar({required final ChatOptions options}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ChatBottomBarState();
}

class _ChatBottomBarState() extends ConsumerState<_ChatBottomBar> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.text = ref.read(chatNotifierProvider(widget.options)).chatInputDraft;
    _textController.addListener(() {
      ref.read(chatNotifierProvider(widget.options)).chatInputDraft = _textController.text;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider);
    final sendButton = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textController,
      builder: (context, value, child) => SemanticIconButton(
        onPressed: authUser != null && value.text.isNotEmpty
            ? () {
                ref.read(chatNotifierProvider(widget.options)).postMessage(_textController.text);
                _textController.clear();
              }
            : null,
        icon: const Icon(Icons.send),
        padding: EdgeInsets.zero,
        semanticsLabel: context.l10n.send,
      ),
    );
    final placeholder = authUser != null ? context.l10n.talkInChat : context.l10n.loginToChat;
    return ChatComposerInput(
      appearance: .room,
      hintText: placeholder,
      sendButton: sendButton,
      controller: _textController,
      readOnly: authUser == null,
    );
  }
}
