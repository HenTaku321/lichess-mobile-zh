// The xiangqi.com private-message protocol, and the model that reads it.
//
// ## Why this is a socket protocol and not REST
//
// xiangqi.com has no inbox endpoint this app can call: the conversation list and every conversation
// arrive as `42/xiangqi` events on the realtime socket, and everything is asked for by emitting
// another event. So an inbox read is a *conversation* — emit, wait for the event — rather than a
// request and a response, and that is the reason for the queue and the spacer below.
//
// ## The four protocol facts that shape this file
//
// 1. **`inbox.chat.user.messages` carries no chat id.** The frame names neither the conversation
//    nor the peer, only the `sender_id` of each message. So the only thing that says whose messages
//    arrived is *what was asked for last*: at most one `inbox.chat.user` may be in flight, and the
//    answers are matched against a queue in the order the questions went out. Two at once would
//    cross two conversations. This is measured — the capture's `inbox.chat.user.messages` frames
//    (主动私信.har, entries 12/14/18) carry no chat id — and it is the rule the Rust reference
//    follows (`listen.rs`, `handle_inbox_messages`: the front of the queue is what recovers the
//    context a response left out).
//
// 2. **Inbox emits are never acked.** The capture contains zero `43/xiangqi` frames. Every emit here
//    is [XiangqiSocketClient.emitNoAck]; the answer, when there is one, is an *event* on the stream
//    (`inbox.chats`, `inbox.chat.user.messages`, `inbox.chat.user.msg.success`).
//    `inbox.chat.mark.read` and the typing events have no answer at all.
//
// 3. **Requests sent too close together are dropped silently** — no error frame, no response. The
//    measured curve is 0 ms → about a fifth of a burst lost, 1000 ms → none
//    (`kXiangqiMinRequestSpacing` documents it for REST). The socket client deliberately has no
//    spacing of its own — its contract is "emit sends immediately", and the online-game controller
//    shares it and does not want a hidden delay on a move — so the gap lives here, at the call
//    site, in [XiangqiSocketRequestQueue].
//
// 4. **`chat.agreement` must never be sent.** On a guest connection it silently mutes the whole
//    session: no error, no disconnect, and everything after it is dropped
//    (`~/rust/xiangqi-tg/src/backfill.rs:329-335`). Nothing here emits it, and nothing here ever
//    should.
//
// ## Guests
//
// Whether a guest can read the inbox at all is **not established**: every capture of it comes from
// a full account, and the one switch that could probe it has no recorded output. So this file does
// not special-case guests — it sends the same frames to a guest session as to an account one. The
// payloads carry no identity of their own (the token does), so if the backend allows guests it
// simply works, and if it does not then the list is empty, which is no worse than before this file
// existed.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_link.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart'
    show XiangqiAuthStorage, kXiangqiMinRequestSpacing, xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket_request_queue.dart';
import 'package:logging/logging.dart';

part 'xiangqi_inbox_repository.freezed.dart';

final _logger = Logger('XiangqiInbox');

/// The chat list, asked for with `{"page": 1}` and answered by the [kXiangqiInboxChatsEvent] event.
const kXiangqiInboxJoinEvent = 'inbox.join';

/// The chat list, server to client.
const kXiangqiInboxChatsEvent = 'inbox.chats';

/// One conversation's message page, asked for with `{"chat_id": "<id>"}`.
const kXiangqiInboxChatUserEvent = 'inbox.chat.user';

/// The message page, server to client. Carries no chat id — see the file header.
const kXiangqiInboxUserMessagesEvent = 'inbox.chat.user.messages';

/// A message to send: `sender_id`, `receiver_username`, `receiver_id`, `message`, `chat_id`.
const kXiangqiInboxNewMessageEvent = 'inbox.chat.user.new.message';

/// A message that was created or arrived, server to client.
///
/// This is both the echo of this device's own send and the peer's reply: the capture shows the same
/// event carrying the `sender_id` of whoever sent it either way (entries 44 and 68), so the sender
/// is what tells the two apart, never the event name.
const kXiangqiInboxMessageSentEvent = 'inbox.chat.user.msg.success';

/// A conversation that did not exist before, server to client.
const kXiangqiInboxNewChatEvent = 'inbox.new.chat';

/// Marks a conversation read, `{"chat_id": "<id>"}`. No reply was observed.
const kXiangqiInboxMarkReadEvent = 'inbox.chat.mark.read';

/// Leaves the inbox, `{"chat_id": null}`. No reply.
const kXiangqiInboxLeaveEvent = 'inbox.leave';

/// How long a single inbox round trip is given before it is treated as dropped.
///
/// The server is known to drop requests silently, so a request with no answer has to be given up on
/// rather than waited on forever. This is generous next to the spacing that separates two requests.
const kXiangqiInboxResponseTimeout = Duration(seconds: 20);

/// The prefix every xiangqi.com user id is given before it enters this app's id space.
///
/// [LightUser.id] is a lichess-shaped [UserId] — a string — and xiangqi.com's ids are integers
/// (`user_id: 200001`). Namespacing does two things at once: it lets an integer id live in a
/// string-typed field, and it is the implementation of "alice on lichess is not alice on
/// xiangqi.com" — the same display name on the two services produces two different ids, and
/// nothing in this file ever compares the two by name.
const kXiangqiUserIdPrefix = 'xq:';

/// [id] (xiangqi.com's own user id) as a [UserId] that cannot collide with a lichess one.
UserId xiangqiUserId(Object? id) => UserId('$kXiangqiUserIdPrefix$id');

/// The [LightUser] for a xiangqi.com account: no title, no flair, no patron colour, because
/// xiangqi.com has none of the three and inventing them would be dressing one service in another's
/// attributes.
LightUser xiangqiLightUser(Object? id, String name) => LightUser(id: xiangqiUserId(id), name: name);

/// A xiangqi.com session failure that has nothing to do with a particular request.
class const XiangqiInboxException(final String message) implements Exception {
  @override
  String toString() => 'XiangqiInboxException: $message';
}

/// One conversation as the server names it, before it is mapped to a row.
///
/// Not a [Contact]: the chat list shows the same fields a chess contact row shows, but the two are
/// built from different protocols and the row that shows them has to be able to tell them apart —
/// see [Contact.xiangqi]. This is the intermediate the parse produces, so the shape of the wire
/// (`user_id`, `unread_messages`, `last_seen`) is written down once, in a type, instead of inside a
/// mapper that builds a lichess object field by field.
@freezed
sealed class const XiangqiChat._() with _$XiangqiChat {
  const factory({
    required String chatId,
    required int peerId,
    required String peerName,
    required String lastMessage,
    required DateTime lastSeen,
    required int unreadMessages,
    @Default(false) bool peerProfileAvailable,
  }) = _XiangqiChat;
}

/// The conversation state the conversation screen draws.
///
/// It holds a [Convo] and a [LightUser] `me`, which is the lichess model reused rather than a
/// xiangqi copy of it: the things a conversation screen needs — a peer, a list of [Message]s, and
/// who this device is — are the same on both backends, and reusing the type keeps the two
/// conversation screens reading one shape.
@freezed
sealed class const XiangqiConversationState._() with _$XiangqiConversationState {
  const factory({required Convo convo, required LightUser me}) = _XiangqiConversationState;
}

/// The identity of one xiangqi.com conversation: enough to fetch it, to send to it and to name it.
///
/// A record rather than a bare chat id, because the chat list is where the peer's name and id come
/// from and the conversation screen is opened straight off a list row — by the time the controller
/// builds there is no list left to ask.
typedef XiangqiConversationKey = ({String chatId, int peerId, LightUser peer});

/// One conversation's messages, on xiangqi.com.
final xiangqiConversationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<XiangqiConversationController, XiangqiConversationState, XiangqiConversationKey>(
      XiangqiConversationController.new,
      name: 'XiangqiConversationControllerProvider',
    );

/// One conversation on xiangqi.com, open in the conversation screen.
///
/// The conversation is read once, when the screen opens, and then kept up to date by the messages
/// the server pushes into it. There is no paging: the page-1 frame carries the newest page and the
/// screen has nowhere to scroll back through yet, so asking for page 2 would be a request with no
/// control behind it.
class XiangqiConversationController(final XiangqiConversationKey key)
    extends AsyncNotifier<XiangqiConversationState> {
  /// This device's own id **on xiangqi.com**, namespaced.
  ///
  /// Kept apart from the state's `me` on purpose. `me` is the app-level identity and follows the
  /// project's scalar rule (a lichess account when there is one); this is the id a message's
  /// `sender_id` is written in, which is a xiangqi id and could never be a lichess one. Comparing
  /// a message against `me` would mark every message as the peer's.
  ///
  /// Re-assigned on every [build] rather than once: the notifier is rebuilt whenever a provider it
  /// watches changes — `authControllerProvider` alone changes once, when its own load lands — and a
  /// `late final` would throw on the second build. Both readers run only on a built state, so it is
  /// never read before it is set.
  UserId? _myId;
  int _generation = 0;
  bool _sending = false;

  /// The texts this device has sent that the server has not echoed back yet.
  ///
  /// The echo of a send arrives under the same event as a peer's message, and without this the
  /// screen would show the sent message twice — once from the optimistic insert below and once from
  /// the echo.
  final List<String> _pendingEchoes = [];

  @override
  Future<XiangqiConversationState> build() async {
    final generation = ++_generation;
    _sending = false;
    _pendingEchoes.clear();
    ref.onDispose(() => _generation++);
    ref.watch(xiangqiAccountGenerationProvider);
    final lichessMe = ref.watch(authControllerProvider)?.user;
    final repo = ref.watch(xiangqiInboxRepositoryProvider);
    final session = await ref.read(xiangqiSessionStoreProvider).read();
    if (!ref.mounted || generation != _generation) throw StateError('Conversation load cancelled.');
    if (session == null) {
      throw const XiangqiInboxException('No xiangqi.com session to open a conversation with.');
    }
    final xiangqiMe = xiangqiLightUser(session.userId, session.name);
    _myId = xiangqiMe.id;
    final messages = await repo.loadMessages(key.chatId);
    if (!ref.mounted || generation != _generation) throw StateError('Conversation load cancelled.');

    // Best effort: the server keeps the unread count, and the chat list is refreshed when this
    // screen pops, so a marker that never lands is corrected by the next `inbox.join` rather than
    // kept wrong here.
    unawaited(repo.markRead(key.chatId).catchError((Object _) {}));

    final incoming = repo.incomingMessages.listen((message) {
      if (!ref.mounted || generation != _generation) return;
      _onIncomingMessage(message);
    });
    ref.onDispose(() {
      unawaited(incoming.cancel());
    });

    return XiangqiConversationState(
      // The app's identity of record for this conversation, by the project's scalar rule: the
      // lichess account when there is one, the xiangqi one only when there is not. It is the
      // identity the app knows this user by, not the identity its messages are stamped with — which
      // is [_myId] — so which side a bubble sits on is decided against the peer, not against this.
      me: lichessMe ?? xiangqiMe,
      convo: Convo(
        user: key.peer,
        messages: messages,
        // No observed xiangqi counterpart to lichess's in/out relation flags. Null is the honest
        // reading, and the app has no control that reads them.
        relations: (inward: null, outward: null),
        // Sending to a non-friend is allowed on xiangqi.com — the capture opens a conversation with
        // a stranger and sends to it (entry 42) — so the composer is always offered. This is a
        // product judgement from that one measured send, not a field the server ever sends.
        postable: true,
      ),
    );
  }

  /// Whether a message was sent by this device.
  ///
  /// Decided against the peer, not against `me`: a xiangqi `sender_id` is a xiangqi id, and `me`
  /// may be a lichess account, so the only id the two sides of this conversation share is the
  /// peer's. A 1:1 conversation has exactly two participants, so "not the peer" is "this device".
  bool _isMine(Message message) => message.userId != xiangqiUserId(key.peerId);

  /// Sends [text] to the peer, showing it at once.
  ///
  /// The message is inserted optimistically and the server's own echo replaces it when it arrives:
  /// the echo carries the server's timestamp, but waiting for it would leave the input standing
  /// silent for as long as the round trip takes.
  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.hasValue || _sending) return false;
    final current = state.requireValue;
    final myId = _myId;
    if (myId == null) return false;
    final generation = _generation;
    _sending = true;
    final repo = ref.read(xiangqiInboxRepositoryProvider);
    final optimistic = Message(userId: myId, text: trimmed, date: clock.now());

    _pendingEchoes.add(trimmed);
    state = AsyncData(
      current.copyWith(
        convo: current.convo.copyWith(messages: current.convo.messages.insert(0, optimistic)),
      ),
    );

    try {
      await repo.sendMessage(
        chatId: key.chatId,
        peerId: key.peerId,
        peerName: key.peer.name,
        text: trimmed,
      );
      return ref.mounted && generation == _generation;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not send to ${key.peer.name} (chat ${key.chatId}).',
        error,
        stackTrace,
      );
      if (!ref.mounted || generation != _generation) return false;
      _pendingEchoes.remove(trimmed);
      if (!state.hasValue) return false;
      final latest = state.requireValue;
      // The row is rolled back by identity, not by position: a message from the peer can land at
      // the front while this send is in flight, and dropping whatever is first would drop theirs.
      if (latest.convo.messages.contains(optimistic)) {
        state = AsyncData(
          latest.copyWith(
            convo: latest.convo.copyWith(messages: latest.convo.messages.remove(optimistic)),
          ),
        );
      }
      return false;
    } finally {
      if (generation == _generation) _sending = false;
    }
  }

  /// Reads a message the server pushed at this socket.
  ///
  /// Only the peer's messages are inserted. This device's own sends come back as an echo under the
  /// same event name, and [sendMessage] has already shown them.
  void _onIncomingMessage(Message message) {
    if (!state.hasValue) return;
    if (_isMine(message)) {
      // Our own echo, under a timestamp the server chose. It replaces the optimistic row's local
      // clock reading rather than joining it. Only a text this session actually sent is consumed:
      // an echo for something sent elsewhere must not overwrite a history row sharing its text.
      if (!_pendingEchoes.remove(message.text)) return;
      final myId = _myId;
      final current = state.requireValue;
      final index = current.convo.messages.indexWhere(
        (m) => m.userId == myId && m.text == message.text,
      );
      if (index == -1) return;
      state = AsyncData(
        current.copyWith(
          convo: current.convo.copyWith(messages: current.convo.messages.replace(index, message)),
        ),
      );
      return;
    }

    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        convo: current.convo.copyWith(messages: current.convo.messages.insert(0, message)),
      ),
    );
    unawaited(
      ref.read(xiangqiInboxRepositoryProvider).markRead(key.chatId).catchError((Object _) {}),
    );
  }
}

/// The xiangqi.com inbox, with an owned, replaceable transport and a serial no-ID read queue.
///
/// The root socket supplies session acquisition only. Closing or resetting this repository never
/// touches notifications, games, reviews, or the root socket.
class XiangqiInboxRepository({
  required final XiangqiSocketClient _socket,
  required final XiangqiAuthStorage _storage,
  final XiangqiSessionStore? sessionStore,
  final Duration _spacing = kXiangqiMinRequestSpacing,
  final Duration _responseTimeout = kXiangqiInboxResponseTimeout,
}) {
  late final _requests = XiangqiSocketRequestQueue(
    socket: _socket,
    spacing: _spacing,
    timeout: _responseTimeout,
  );
  StreamSubscription<XiangqiSocketEvent>? _subscription;
  final _incoming = StreamController<Message>.broadcast();
  bool _disposed = false;

  Stream<Message> get incomingMessages => _incoming.stream;
  Stream<void> get connectionResets => _requests.resets;

  Future<IList<Contact>> loadChats() async => (await loadChatsPage(1)).items;

  Future<XiangqiPage<Contact>> loadChatsPage(int page) {
    if (_disposed) return Future.error(const XiangqiInboxException('This repository is disposed.'));
    if (page < 1) return Future.error(RangeError.range(page, 1, null, 'page'));
    _ensureListening();
    int? generation;
    return _requests.read(
      event: kXiangqiInboxJoinEvent,
      data: {'page': page},
      response: kXiangqiInboxChatsEvent,
      decode: (payload) => xiangqiContactsPageFromPayload(payload, requestedPage: page),
      key: ('chats', sessionStore?.accountGeneration, page),
      prepare: () async {
        await sessionStore?.ready;
        generation = sessionStore?.accountGeneration;
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == sessionStore?.accountGeneration),
    );
  }

  Future<IList<Message>> loadMessages(String chatId) async =>
      (await loadMessagesPage(chatId, 1)).items;

  Future<XiangqiPage<Message>> loadMessagesPage(String chatId, int page) {
    if (_disposed) return Future.error(const XiangqiInboxException('This repository is disposed.'));
    if (page < 1) return Future.error(RangeError.range(page, 1, null, 'page'));
    _ensureListening();
    int? generation;
    return _requests.read(
      event: kXiangqiInboxChatUserEvent,
      data: {'chat_id': chatId, 'page': page},
      response: kXiangqiInboxUserMessagesEvent,
      decode: (payload) => xiangqiMessagesPageFromPayload(payload, requestedPage: page),
      key: ('messages', sessionStore?.accountGeneration, chatId, page),
      prepare: () async {
        await sessionStore?.ready;
        generation = sessionStore?.accountGeneration;
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == sessionStore?.accountGeneration),
    );
  }

  /// No ACK or delivery receipt is invented. The return value only confirms local emission.
  Future<void> sendMessage({
    required String chatId,
    required int peerId,
    required String peerName,
    required String text,
  }) {
    int? generation;
    final payload = <String, Object?>{
      'receiver_username': peerName,
      'receiver_id': peerId,
      'message': text,
      'chat_id': chatId.isEmpty ? null : chatId,
    };
    _ensureListening();
    return _requests.sendNoAck(
      kXiangqiInboxNewMessageEvent,
      data: payload,
      prepare: () async {
        final session = await (sessionStore?.read() ?? _storage.read());
        if (session == null) {
          throw const XiangqiInboxException('No xiangqi.com session to send with.');
        }
        generation = sessionStore?.accountGeneration;
        payload['sender_id'] = _xiangqiJsonId(session.userId);
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == sessionStore?.accountGeneration),
    );
  }

  Future<void> markRead(String chatId) {
    _ensureListening();
    int? generation;
    return _requests.sendNoAck(
      kXiangqiInboxMarkReadEvent,
      data: {'chat_id': chatId},
      prepare: () async {
        await sessionStore?.ready;
        generation = sessionStore?.accountGeneration;
      },
      isCurrent: () =>
          !_disposed && (generation == null || generation == sessionStore?.accountGeneration),
    );
  }

  Future<void> leave() {
    if (_disposed || !_requests.isConnected) return Future<void>.value();
    final generation = sessionStore?.accountGeneration;
    return _requests.sendNoAck(
      kXiangqiInboxLeaveEvent,
      data: const {'chat_id': null},
      isCurrent: () => !_disposed && generation == sessionStore?.accountGeneration,
    );
  }

  void _ensureListening() {
    _subscription ??= _requests.events.listen((event) {
      if (_disposed || event.name != kXiangqiInboxMessageSentEvent) return;
      final message = xiangqiMessageFromPayload(_unwrap(event.data));
      if (message != null && !_incoming.isClosed) _incoming.add(message);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _requests.dispose(lastEvent: kXiangqiInboxLeaveEvent, lastData: const {'chat_id': null});
    unawaited(_incoming.close());
  }
}

XiangqiPage<Contact> xiangqiContactsPageFromPayload(Object? payload, {required int requestedPage}) {
  final envelope = _asMap(_unwrap(payload));
  final rows = envelope?['items'];
  if (envelope == null || rows is! List) {
    throw const FormatException('Invalid xiangqi.com inbox page envelope.');
  }
  final items = xiangqiContactsFromChats(payload);
  if (rows.isNotEmpty && items.isEmpty) {
    throw const FormatException('The xiangqi.com inbox page contains no readable contacts.');
  }
  return XiangqiPage.fromMetadata(items: items, requestedPage: requestedPage, metadata: envelope);
}

XiangqiPage<Message> xiangqiMessagesPageFromPayload(Object? payload, {required int requestedPage}) {
  final envelope = _asMap(_unwrap(payload));
  final rows = envelope?['items'];
  if (envelope == null || rows is! List) {
    throw const FormatException('Invalid xiangqi.com message page envelope.');
  }
  final items = xiangqiMessagesFromPayload(payload);
  if (rows.isNotEmpty && items.isEmpty) {
    throw const FormatException('The xiangqi.com message page contains no readable messages.');
  }
  return XiangqiPage.fromMetadata(items: items, requestedPage: requestedPage, metadata: envelope);
}

/// The chat list of an `inbox.chats` payload, as [Contact]s.
///
/// A row that cannot be read is dropped rather than repaired: every [Contact] field is required, so
/// the alternative to dropping one is inventing a name, a date or an unread count the server never
/// sent. Dropping a conversation is visible and recoverable (the next `inbox.join` brings it back);
/// a fabricated field is neither.
IList<Contact> xiangqiContactsFromChats(Object? payload) =>
    xiangqiChatsFromPayload(payload).map(_contactOf).toIList();

/// The [Contact] for one parsed chat.
Contact _contactOf(XiangqiChat chat) {
  final peer = xiangqiLightUser(chat.peerId, chat.peerName);
  return Contact(
    user: peer,
    // `last_message` is the text and `last_seen` is when it was sent: the two fields the row shows.
    // `read` and `userId` exist because the lichess shape requires them, and neither is what decides
    // this row's unread dot — see [Contact.xiangqi]. `userId` is the peer, the only other party a
    // 1:1 chat can have, and `read` is the count flattened to the one bit there is room for.
    lastMessage: LastMessage(
      userId: peer.id,
      text: chat.lastMessage,
      date: chat.lastSeen,
      read: chat.unreadMessages == 0,
    ),
    xiangqi: XiangqiConversation(
      chatId: chat.chatId,
      peerId: chat.peerId,
      unreadMessages: chat.unreadMessages,
      peerProfileAvailable: chat.peerProfileAvailable,
    ),
  );
}

/// The chats of an `inbox.chats` payload.
IList<XiangqiChat> xiangqiChatsFromPayload(Object? payload) {
  final chats = <XiangqiChat>[];
  for (final item in _itemsOf(payload)) {
    final map = _asMap(item);
    if (map == null) continue;
    final chatId = _asString(map['chat_id']);
    final peerId = _asInt(map['user_id']);
    final peerName = _asString(map['username']);
    final lastMessage = _asString(map['last_message']);
    final lastSeen = _parseXiangqiDate(map['last_seen']);
    if (chatId == null ||
        chatId.isEmpty ||
        peerId == null ||
        peerName == null ||
        peerName.isEmpty ||
        lastMessage == null ||
        lastSeen == null) {
      _logger.warning('An inbox chat row could not be read and was dropped.');
      continue;
    }
    chats.add(
      XiangqiChat(
        chatId: chatId,
        peerId: peerId,
        peerName: peerName,
        lastMessage: lastMessage,
        lastSeen: lastSeen,
        unreadMessages: _asInt(map['unread_messages']) ?? 0,
        peerProfileAvailable: map['hidden_username'] != true && isXiangqiProfileName(peerName),
      ),
    );
  }
  return chats.lock;
}

/// The messages of an `inbox.chat.user.messages` payload, newest first.
///
/// The server's own order, kept: the list is newest-first on the wire (capture entry 12), and the
/// conversation screen renders it that way.
IList<Message> xiangqiMessagesFromPayload(Object? payload) {
  final messages = <Message>[];
  for (final item in _itemsOf(payload)) {
    final message = xiangqiMessageFromPayload(item);
    if (message != null) messages.add(message);
  }
  return messages.lock;
}

/// One message of an item payload, or null if it cannot be read.
///
/// Used both for a page's entries and for the object of an `inbox.chat.user.msg.success` frame,
/// which carries the same four fields — the caller unwraps that frame's `data` envelope first,
/// because a page's entries have none.
Message? xiangqiMessageFromPayload(Object? value) {
  final map = _asMap(value);
  if (map == null) return null;
  final text = _asString(map['message']);
  final senderId = _asInt(map['sender_id']);
  final date = _parseXiangqiDate(map['created_on']);
  if (text == null || senderId == null || date == null) return null;
  return Message(userId: xiangqiUserId(senderId), text: text, date: date);
}

/// A server frame's payload without its envelope: `{"data": {...}}` → `{...}`.
///
/// Every inbox frame this app reads nests the useful object one level down under `data`, so a
/// reader that wants a field has to unwrap first. Left alone when there is no envelope, so that it
/// is safe to call on a payload that is already bare.
Object? _unwrap(Object? payload) {
  final map = _asMap(payload);
  return map?['data'] ?? map;
}

/// The `items` array of a page payload: `{"data": {"items": [...]}}`, as every page frame spells it.
List<Object?> _itemsOf(Object? payload) {
  final items = _asMap(_unwrap(payload))?['items'];
  return items is List ? items : const [];
}

/// xiangqi.com's timestamps, as `DateTime.parse` reads them.
///
/// The server writes ISO-8601 with no timezone designator (`2024-05-06T09:12:33.123456`), where
/// lichess writes epoch milliseconds — which is why the chess mapper's date reader
/// (`asDateTimeFromMillisecondsOrThrow`) cannot read one of these. Whether the server means UTC is
/// **not established** — no frame in the capture says, and nothing here ever compares one of these
/// against a lichess timestamp — so this makes it a `DateTime` and claims nothing more. The only
/// thing that reads it is a relative-date label.
DateTime? _parseXiangqiDate(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// [id] as the JSON number it is for an account, or the string it is for a guest.
///
/// A guest's `sub` is a string (`guest7zuq8`) and an account's is a number (`100001`); the capture
/// only ever shows the number, because every capture of the inbox is from an account. Writing the
/// string back for a guest is the honest thing to send — it is the value the token itself carries,
/// and the alternative is to invent a number for it.
Object _xiangqiJsonId(String id) => int.tryParse(id) ?? id;

/// [value] as a string-keyed map, or null if it is not one.
///
/// Built by hand rather than with `Map.cast`, which is lazy: a cast map throws where it is read,
/// which would be somewhere far from the frame that was wrong.
Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) map[key] = entry.value;
  }
  return map;
}

String? _asString(Object? value) => value is String ? value : null;

/// [value] as an int, or null. JSON gives a whole number back as an `int`, but one written with a
/// point comes back as a `double` and is taken as one too.
int? _asInt(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : null;

/// The xiangqi.com inbox: one repository for the app.
///
/// Not `autoDispose`: the serialising queue inside it is a property of the socket connection, and a
/// queue that went away with the contacts screen would let two screens ask at once. It owns its
/// forked transport; the root [xiangqiSocketProvider] supplies session acquisition only.
final xiangqiInboxRepositoryProvider = Provider<XiangqiInboxRepository>((Ref ref) {
  ref.watch(xiangqiAccountGenerationProvider);
  final sessions = ref.read(xiangqiSessionStoreProvider);
  final repository = XiangqiInboxRepository(
    socket: ref.read(xiangqiSocketProvider),
    storage: ref.read(xiangqiAuthStorageProvider),
    sessionStore: sessions,
  );
  ref.onDispose(repository.dispose);
  return repository;
}, name: 'XiangqiInboxRepositoryProvider');

/// The xiangqi.com side of the contacts list.
///
/// Empty, not an error, when there is no xiangqi.com session: there is nothing to ask for and no
/// token to ask with, and an empty list is exactly what "no conversations" looks like. When there
/// *is* a session the same frames go out whatever kind of session it is — see the file header on
/// why guests are not special-cased here. Follow account boundaries, not token revisions, so a
/// refresh does not clear the loaded list or enqueue another inbox request.
final xiangqiContactsProvider = FutureProvider.autoDispose<IList<Contact>>((ref) async {
  ref.watch(xiangqiAccountGenerationProvider);
  final repository = ref.watch(xiangqiInboxRepositoryProvider);
  final store = ref.read(xiangqiSessionStoreProvider);
  final session = await store.read();
  if (!ref.mounted || session == null) return const IListConst<Contact>([]);
  final contacts = await repository.loadChats();
  return contacts;
}, name: 'XiangqiContactsProvider');

/// The signed-in xiangqi.com account as a [LightUser], or null when there is no session.
///
/// The namespaced id is this device's identity *inside xiangqi.com*, which is what a conversation's
/// messages are compared against — a lichess id could never match a xiangqi `sender_id`.
Future<LightUser?> xiangqiSelfLightUser(Ref ref) async {
  final session = await ref.read(xiangqiSessionStoreProvider).read();
  return session == null ? null : xiangqiLightUser(session.userId, session.name);
}
