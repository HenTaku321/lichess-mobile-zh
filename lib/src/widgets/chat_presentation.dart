import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:material_ui/material_ui.dart';

/// Public rooms and private conversations already have two intentional visual treatments. Backend
/// choice is not a treatment: chess and xiangqi use the same surface for the same kind of chat.
enum ChatAppearance() {
  room,
  conversation,
}

class const ChatBubbleSurface({
  required final ChatAppearance appearance,
  required final bool isMine,
  required final Widget child,
  final int groupLength = 1,
  final int groupIndex = 0,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final private = appearance == .conversation;
    final scheme = ColorScheme.of(context);
    final grouped = private && groupLength > 1;
    final first = groupIndex == 0;
    final last = groupIndex == groupLength - 1;
    const radius = Radius.circular(16);
    const groupRadius = Radius.circular(4);
    final background = private
        ? (isMine ? scheme.secondaryContainer : scheme.surfaceContainer)
        : (isMine ? scheme.secondary : scheme.surfaceContainerHigh);
    final foreground = private
        ? (isMine ? scheme.onSecondaryContainer : scheme.onSurface)
        : (isMine ? scheme.onSecondary : scheme.onSurface);
    return FractionallySizedBox(
      alignment: isMine ? .centerRight : .centerLeft,
      widthFactor: private ? 0.85 : 0.9,
      child: Align(
        alignment: isMine ? .centerRight : .centerLeft,
        child: Container(
          margin: private
              ? EdgeInsets.only(
                  bottom: !grouped || first ? 8 : 2,
                  top: !grouped || last ? 8 : 2,
                  left: 8,
                  right: 8,
                )
              : const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: private ? 14 : 15),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: !isMine && grouped && !last ? groupRadius : radius,
              topRight: isMine && grouped && !last ? groupRadius : radius,
              bottomLeft: !isMine && grouped && !first ? groupRadius : radius,
              bottomRight: isMine && grouped && !first ? groupRadius : radius,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Link gestures and the timestamp's last-line reservation have one implementation. User/room
/// identity and link routing remain supplied by the protocol-specific screen.
class const ChatMessageContent({
  required final String text,
  required final LinkCallback onLinkOpen,
  final List<Linkifier> linkifiers = defaultLinkifiers,
  final Widget? sender,
  final String? time,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final timestamp = time;
    final timeStyle = TextStyle(
      fontSize: 11,
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.6),
    );
    final text = RichLinkText(
      text: this.text,
      linkifiers: linkifiers,
      linkStyle: Styles.linkStyle,
      onOpen: onLinkOpen,
      trailing: timestamp == null
          ? null
          : WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Opacity(
                opacity: 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(timestamp, style: timeStyle),
                ),
              ),
            ),
    );
    return timestamp != null
        ? Stack(
            children: [
              text,
              Positioned(right: 0, bottom: 0, child: Text(timestamp, style: timeStyle)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?sender, text],
          );
  }
}

class const ChatDaySeparator({required final DateTime date, super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final day = DateTime(date.year, date.month, date.day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          decoration: BoxDecoration(
            color: ColorScheme.of(context).tertiaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            day == today
                ? context.l10n.today
                : day == yesterday
                ? context.l10n.yesterday
                : DateFormat.yMMMd().format(date),
            style: TextStyle(
              color: ColorScheme.of(context).onTertiaryContainer.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reverse chronology, safe-area padding and tapping empty message space to dismiss the keyboard
/// are presentation rules, independent of page tokens, typing events or message identifiers.
class const ChatMessageList({
  required final int itemCount,
  required final IndexedWidgetBuilder itemBuilder,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    child: ListView.builder(
      padding: MediaQuery.paddingOf(context).copyWith(bottom: 0),
      reverse: true,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    ),
  );
}

/// Shared geometry and keyboard defaults only. Draft storage, dispatch, permission checks and
/// busy/error feedback stay in their controllers and callers.
class const ChatComposerInput({
  required final ChatAppearance appearance,
  required final TextEditingController controller,
  required final Widget sendButton,
  final String? hintText,
  final bool readOnly = false,
  final bool? enabled,
  final TextInputAction? textInputAction,
  final ValueChanged<String>? onSubmitted,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: appearance == .conversation
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
          suffixIcon: sendButton,
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
          hintText: hintText,
        ),
        controller: controller,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
        minLines: 1,
        maxLines: 4,
        enableSuggestions: true,
        readOnly: readOnly,
        enabled: enabled,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
      ),
    ),
  );
}
