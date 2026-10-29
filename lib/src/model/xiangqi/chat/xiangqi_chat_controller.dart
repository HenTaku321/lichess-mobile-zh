import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:logging/logging.dart';

part 'xiangqi_chat_controller.freezed.dart';

final _logger = Logger('XiangqiChat');

/// The shortest gap between two requests on a chat connection.
///
/// One and a half seconds, and it is not a courtesy: xiangqi.com **silently drops** requests that
/// arrive closer together — no error frame, no disconnect, nothing. Measured against the live host
/// by `xiangqi-tg` on 2026-08-29: 0 ms spacing lost about a fifth of a burst, 600 ms lost one in
/// twenty, and 1000 ms lost none. The same 1500 ms the HTTP client uses is used here, for the same
/// reason and with the same margin. See `xiangqi-com-re/docs/chat.md`.
///
/// It is counted **per connection** and it does not accumulate while idle: this is a floor between
/// two requests, not a bucket that fills up.
const Duration kXiangqiChatRequestSpacing = Duration(milliseconds: 1500);

/// Which chat is being read: a public room, or one game's own.
///
/// A record rather than a class, because the two fields are the whole of it and a family's key has
/// to be equal by value.
typedef XiangqiChatRoomKey = ({XiangqiChatKind kind, String room});

/// What a chat can fail at.
enum XiangqiChatError() {
  /// The socket never came up, which is a chat that cannot be read or written.
  offline,

  /// A page of history was asked for and did not arrive.
  history,

  /// The server refused something that was sent.
  send,
}

/// One room's chat, as it stands.
@freezed
sealed class const XiangqiChatState._() with _$XiangqiChatState {
  const factory({
    /// Whether the socket is up. A chat with no connection is a chat that cannot be written in.
    @Default(false) bool isConnected,

    /// Whether the first page is still being asked for.
    @Default(false) bool isLoading,

    /// Whether an older page is being asked for.
    @Default(false) bool isLoadingMore,

    /// Whether there is an older page to ask for.
    @Default(false) bool hasMore,

    /// The messages, oldest first — the order they are read in.
    @Default(IListConst<XiangqiChatMessage>([])) IList<XiangqiChatMessage> messages,

    /// What went wrong, if anything did.
    XiangqiChatError? error,
  }) = _XiangqiChatState;

  /// Whether the room has nothing in it, and is not still finding that out.
  bool get isEmpty => messages.isEmpty && !isLoading && error == null;
}

/// One room's chat, read on a socket of its own.
///
/// ## Why a socket of its own
///
/// **One connection carries one room.** The new-message broadcast,
/// `chat.new.lobby.message.success`, has no `room` field: two rooms on one connection are two
/// streams that cannot be told apart. The site's own client opens a connection per room, and so does
/// this — which is also why the chat never shares the socket an online game is being played on.
///
/// ## What is not sent
///
/// `chat.agreement` is not sent, ever. It reads like a handshake and is not one: a guest that sends
/// it has its whole session go quiet — no error, no disconnect, every later request dropped — and
/// reading a room's history does not need it. See `xiangqi-com-re/docs/chat.md`.
///
/// ## Sending has no receipt
///
/// The server does not ack a message. The only proof one landed is the echo: the same message comes
/// back on [XiangqiSocketClient.stream] as a broadcast, and the sender's own copy is what is shown.
/// So [send] does not wait for anything, and the input is cleared by the caller rather than by a
/// future that will never complete.
final xiangqiChatControllerProvider = NotifierProvider.autoDispose
    .family<XiangqiChatController, XiangqiChatState, XiangqiChatRoomKey>(
      XiangqiChatController.new,
      name: 'XiangqiChatControllerProvider',
    );

class XiangqiChatController(final XiangqiChatRoomKey key) extends Notifier<XiangqiChatState> {
  XiangqiSocketClient? _socket;
  StreamSubscription<XiangqiSocketEvent>? _events;
  StreamSubscription<void>? _connections;
  StreamSubscription<XiangqiConnectionStatus>? _status;
  Timer? _historyTimeout;

  /// The page the last history request asked for, which is the page its answer is about.
  int _pendingPage = 1;

  /// How far back the reader has read, so that [loadMore] knows what to ask for next.
  int _page = 1;

  /// When the last request went out, which is what [kXiangqiChatRequestSpacing] is counted from.
  DateTime? _lastRequest;

  /// The queue every request waits in, so that two of them cannot both decide the coast is clear.
  Future<void> _turn = Future<void>.value();
  Timer? _spacingTimer;
  Completer<void>? _spacingWaiter;

  @override
  XiangqiChatState build() {
    ref.onDispose(() {
      _events?.cancel();
      _connections?.cancel();
      _status?.cancel();
      _historyTimeout?.cancel();
      _spacingTimer?.cancel();
      _spacingTimer = null;
      final waiter = _spacingWaiter;
      _spacingWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      final socket = _socket;
      _socket = null;
      if (socket != null) unawaited(socket.dispose());
    });

    final socket = ref.read(xiangqiSocketProvider).fork();
    _socket = socket;

    _events = socket.stream.listen(_onEvent);
    _connections = socket.connectedStream.listen((_) => unawaited(_onConnected()));
    _status = socket.statusStream.listen((status) {
      if (!ref.mounted ||
          status == XiangqiConnectionStatus.connected ||
          status == XiangqiConnectionStatus.connecting) {
        return;
      }
      _historyTimeout?.cancel();
      state = state.copyWith(
        isConnected: false,
        isLoading: false,
        isLoadingMore: false,
        error: XiangqiChatError.offline,
      );
    });
    unawaited(
      socket.connect().catchError((Object error, StackTrace stackTrace) {
        _logger.warning('The chat socket could not connect.', error, stackTrace);
        if (ref.mounted) {
          state = state.copyWith(
            error: XiangqiChatError.offline,
            isLoading: false,
            isLoadingMore: false,
            isConnected: false,
          );
        }
      }),
    );

    return const XiangqiChatState(isLoading: true);
  }

  /// Asks for the first page of the room's history.
  ///
  /// The history is the join: there is no separate "enter the room" call, and the reply to this one
  /// is the event that says the connection is in the room.
  Future<void> _onConnected() async {
    if (!ref.mounted) return;
    state = state.copyWith(isConnected: true, error: null);
    await _requestHistory(page: 1);
  }

  /// Asks for one page of the room's history, oldest first once it lands.
  Future<void> _requestHistory({required int page}) async {
    final socket = _socket;
    if (socket == null || !socket.isConnected) return;
    if (page == 1) {
      state = state.copyWith(isLoading: true, error: null);
    } else {
      state = state.copyWith(isLoadingMore: true);
    }
    _pendingPage = page;
    await _waitForTurn();
    if (!ref.mounted || !socket.isConnected) return;
    _historyTimeout?.cancel();
    _historyTimeout = Timer(const Duration(seconds: 20), () {
      if (ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: XiangqiChatError.history,
        );
      }
    });
    // No ack is asked for: the answer to this request is the `chat.lobby.messages.success` event,
    // and the site's own client sends the same frame without an ack id. See the class doc.
    socket.emitNoAck(
      'chat_v2.messages',
      data: {'type': key.kind.wire, 'room': key.room, 'page': page},
    );
  }

  /// Asks for the page before the one already read.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    await _requestHistory(page: _page + 1);
  }

  Future<void> retry() async {
    if (state.isLoading || state.isLoadingMore) return;
    final socket = _socket;
    if (socket == null) return;
    if (!socket.isConnected) {
      try {
        await socket.connect();
      } on Object {
        if (ref.mounted) state = state.copyWith(isLoading: false, error: XiangqiChatError.offline);
      }
    } else {
      await _requestHistory(page: 1);
    }
  }

  /// Sends [text] to the room.
  ///
  /// Nothing is awaited that would say whether it arrived, because nothing would: see the class
  /// doc. The message is shown when the server echoes it back.
  Future<bool> send(String text) async {
    final message = text.trim();
    final socket = _socket;
    if (message.isEmpty || socket == null || !socket.isConnected) return false;
    await _waitForTurn();
    if (!ref.mounted || !socket.isConnected) return false;
    socket.emitNoAck(
      'chat_v2.new.message',
      data: {'type': key.kind.wire, 'room': key.room, 'message': message},
    );
    return true;
  }

  /// Waits out [kXiangqiChatRequestSpacing] since the last request, and marks this one as sent.
  ///
  /// Serialised through a single future so that two callers cannot both decide the coast is clear
  /// and then both send: the second one waits for the first one's turn to end.
  Future<void> _waitForTurn() {
    final previous = _turn;
    final turn = previous.then((_) async {
      if (!ref.mounted) return;
      final last = _lastRequest;
      final now = DateTime.now();
      if (last != null) {
        final earliest = last.add(kXiangqiChatRequestSpacing);
        if (earliest.isAfter(now)) {
          final waiter = Completer<void>();
          _spacingWaiter = waiter;
          _spacingTimer = Timer(earliest.difference(now), waiter.complete);
          await waiter.future;
          if (identical(_spacingWaiter, waiter)) {
            _spacingTimer = null;
            _spacingWaiter = null;
          }
        }
      }
      _lastRequest = DateTime.now();
    });
    _turn = turn;
    return turn;
  }

  void _onEvent(XiangqiSocketEvent event) {
    switch (event.name) {
      case 'chat.lobby.messages.success':
        _onHistory(event.data);
      case 'chat.new.lobby.message.success':
        _onMessage(event.data);
      case 'chat.error':
      case 'chat.new.lobby.message.error':
        if (!ref.mounted) return;
        _historyTimeout?.cancel();
        state = state.copyWith(
          error: state.isLoading || state.isLoadingMore
              ? XiangqiChatError.history
              : XiangqiChatError.send,
          isLoading: false,
          isLoadingMore: false,
        );
    }
  }

  void _onHistory(Object? data) {
    if (!ref.mounted) return;
    _historyTimeout?.cancel();
    final page = xiangqiChatMessagesFromJson(data);
    // An older page goes in front of what is already read; the first page replaces it, which is
    // also what makes a reconnect that re-asks for page one land on the same list rather than on a
    // second copy of it.
    final messages = _pendingPage == 1 ? page : page.followedBy(state.messages).toIList();
    _page = _pendingPage;
    state = state.copyWith(
      messages: messages,
      isLoading: false,
      isLoadingMore: false,
      hasMore: _hasNextPage(data),
      error: null,
    );
  }

  void _onMessage(Object? data) {
    if (!ref.mounted) return;
    final message = xiangqiChatMessageFromJson(data);
    if (message == null) return;
    // The echo of the reader's own message arrives here too, and so does a message the history
    // already carried: the server's id is what tells the two apart.
    final id = message.id;
    if (id != null && state.messages.any((existing) => existing.id == id)) return;
    state = state.copyWith(messages: state.messages.add(message));
  }

  bool _hasNextPage(Object? data) {
    final envelope = data is Map<String, dynamic> ? data['data'] : null;
    return envelope is Map<String, dynamic> && envelope['has_next_page'] == true;
  }
}
