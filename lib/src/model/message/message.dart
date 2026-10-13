import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/utils/json.dart';

part 'message.freezed.dart';

typedef UnreadMessages = ({int unread, bool lichess});

@freezed
sealed class const Contacts._() with _$Contacts {
  const factory({required IList<Contact> contacts, required LightUser me, required bool isBot}) =
      _Contacts;

  factory fromServerJson(Map<String, dynamic> json) {
    return Contacts.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return Contacts(
      contacts: pick('contacts').asListOrEmpty((it) => Contact.fromPick(it)).toIList(),
      me: pick('me').asLightUserOrThrow(),
      isBot: pick('bot').asBoolOrFalse(),
    );
  }

  int get unreadCount {
    return contacts
        .where((contact) => !contact.lastMessage.read && contact.lastMessage.userId != me.id)
        .length;
  }
}

@freezed
sealed class ConversationData with _$ConversationData {
  const factory({required LightUser me, required bool isBot, required Convo convo}) =
      _ConversationData;

  factory fromServerJson(Map<String, dynamic> json) {
    return ConversationData.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return ConversationData(
      me: pick('me').asLightUserOrThrow(),
      isBot: pick('bot').asBoolOrFalse(),
      convo: pick('convo').letOrThrow((it) => Convo.fromPick(it.required())),
    );
  }
}

@freezed
sealed class Message with _$Message {
  const factory({required UserId userId, required String text, required DateTime date}) = _Message;

  factory fromServerJson(Map<String, dynamic> json) {
    return Message.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return Message(
      userId: pick('user').asUserIdOrThrow(),
      text: pick('text').asStringOrThrow(),
      date: pick('date').asDateTimeFromMillisecondsOrThrow(),
    );
  }
}

@freezed
sealed class LastMessage with _$LastMessage {
  const factory({
    required UserId userId,
    required String text,
    required DateTime date,
    required bool read,
  }) = _LastMessage;
}

/// What a [Contact] row needs in order to be a xiangqi.com conversation rather than a lichess one.
///
/// [Contact] is a lichess shape — a user and one last message — and the chat list reads exactly
/// those two things off it whatever backend the row came from. Everything else a conversation needs
/// is written here instead of being forced into the lichess fields: the chat id, which the lichess
/// shape has nowhere to keep and which the conversation screen cannot ask for again, and the unread
/// count, which the row's unread dot is decided by.
///
/// The unread dot is where the two backends genuinely differ, and it is why this is data rather
/// than a flag: lichess marks a message read with a boolean and its own id, while xiangqi.com keeps
/// a per-conversation count of unread messages. A count of zero is read; anything else is not. That
/// is a comparison of the peer's count against zero and never against this user's id, which is what
/// makes it correct for a guest as well — a guest's id is a string (`guest7zuq8`) that could never
/// equal a numeric `user_id` in the first place.
@freezed
sealed class const XiangqiConversation._() with _$XiangqiConversation {
  const factory({required String chatId, required int peerId, required int unreadMessages}) =
      _XiangqiConversation;
}

@freezed
sealed class Contact with _$Contact {
  const factory({
    required LightUser user,
    required LastMessage lastMessage,

    /// Non-null exactly when this row is a xiangqi.com conversation.
    ///
    /// The chat list dispatches on this field and on nothing else — in particular not on
    /// `BackendSource`, which is a model-layer concept that must not reach a widget.
    XiangqiConversation? xiangqi,
  }) = _Contact;

  factory fromServerJson(Map<String, dynamic> json) {
    return Contact.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return Contact(
      user: pick('user').asLightUserOrThrow(),
      lastMessage: LastMessage(
        userId: pick('lastMsg', 'user').asUserIdOrThrow(),
        text: pick('lastMsg', 'text').asStringOrThrow(),
        date: pick('lastMsg', 'date').asDateTimeFromMillisecondsOrThrow(),
        read: pick('lastMsg', 'read').asBoolOrThrow(),
      ),
    );
  }
}

typedef Relations = ({bool? inward, bool? outward});

@freezed
sealed class Convo with _$Convo {
  const factory({
    required LightUser user,
    required IList<Message> messages,
    required Relations relations,
    required bool postable,
    ModDetails? modDetails,
  }) = _Convo;

  factory fromServerJson(Map<String, dynamic> json) {
    return Convo.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return Convo(
      user: pick('user').asLightUserOrThrow(),
      messages: pick('msgs').asListOrThrow((it) => Message.fromPick(it)).toIList(),
      relations: (inward: pick('in').asBoolOrNull(), outward: pick('out').asBoolOrNull()),
      postable: pick('postable').asBoolOrThrow(),
      modDetails: pick('modDetails').letOrNull(
        (it) => (kid: it('kid').asBoolOrThrow(), openInbox: it('openInbox').asBoolOrThrow()),
      ),
    );
  }
}

typedef ModDetails = ({bool kid, bool openInbox});

@freezed
sealed class SearchResult with _$SearchResult {
  const factory({
    required IList<Contact> contacts,
    required IList<LightUser> friends,
    required IList<LightUser> users,
  }) = _SearchResult;

  factory fromJson(Map<String, dynamic> json) {
    return SearchResult.fromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) {
    return SearchResult(
      contacts: pick('contacts').asListOrEmpty((it) => Contact.fromPick(it)).toIList(),
      friends: pick('friends').asListOrEmpty((it) => it.asLightUserOrThrow()).toIList(),
      users: pick('users').asListOrEmpty((it) => it.asLightUserOrThrow()).toIList(),
    );
  }
}
