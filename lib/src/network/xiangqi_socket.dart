// The xiangqi.com realtime socket (Socket.IO v4 over Engine.IO v4), written out by hand.
//
// There is no `socket_io_client` dependency here and there is not going to be one: the protocol
// needs three packet shapes and one heartbeat rule, and the pub package would bring a second
// dependency tree plus its own reconnect policy to a file that already has one.
//
// **Nothing in this file touches `SocketPool`.** The pool's `open()` closes every other connection
// it holds (`socket.dart`, "ensure there is only one active connection"), which is exactly right for
// lichess and exactly what must not happen to a second, unrelated service: opening a xiangqi game
// must not knock the lichess lobby or spectator socket off the air. This client owns its own
// channel, its own provider and its own lifetime, and the test file next to it proves the lichess
// socket survives.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/socket.dart'
    show WebSocketChannelFactory, webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiClientProvider;
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _logger = Logger('XiangqiSocketClient');

/// The Socket.IO namespace everything xiangqi.com does lives in.
const kXiangqiSocketNamespace = '/xiangqi';

/// The host the realtime socket is served from.
const kXiangqiSocketHost = 'api.xiangqi.com';

/// The path of the Engine.IO endpoint.
const kXiangqiSocketPath = '/socket.io/';

/// The heartbeat the server announces in its open frame, used until one arrives.
const kXiangqiDefaultPingInterval = Duration(seconds: 8);

/// How long the server waits for our pong before it drops the connection.
const kXiangqiDefaultPingTimeout = Duration(seconds: 20);

/// The websocket URL for [token].
///
/// The token goes in the query string *and* in the connect packet: the server's own client sends it
/// both ways, and the query is what the handshake is authorised by. A URL carrying a credential
/// must never be logged or put in an error message — see [XiangqiSocketException] and [_redact].
Uri xiangqiSocketUri(String token) => Uri.https(kXiangqiSocketHost, kXiangqiSocketPath, {
  'EIO': '4',
  'transport': 'websocket',
  'jwt': token,
}).replace(scheme: 'wss');

/// A failure of the xiangqi.com socket itself, with the session token already taken out.
class const XiangqiSocketException(final String message) implements Exception {
  @override
  String toString() => 'XiangqiSocketException: $message';
}

/// One decoded frame of the Engine.IO / Socket.IO conversation.
sealed class const XiangqiFrame();

/// The Engine.IO `0` open frame, carrying the heartbeat parameters.
final class const XiangqiOpenFrame(final Map<String, Object?> data) extends XiangqiFrame {
  /// How often the server sends `2`, or null if it did not say.
  Duration? get pingInterval => _millis(data['pingInterval']);

  /// How long the server waits for `3` before dropping the connection, or null if it did not say.
  Duration? get pingTimeout => _millis(data['pingTimeout']);

  /// The largest frame the server will accept, or null if it did not say.
  int? get maxPayload {
    final value = data['maxPayload'];
    return value is int ? value : null;
  }
}

/// An Engine.IO `2` ping.
///
/// The server sends these; a bare `2` is the ordinary shape, and the payload is empty then. This is
/// *not* the same as the bare socket.io event `2[...]`, which [parseXiangqiFrame] tells apart by
/// what follows the `2`.
final class const XiangqiPingFrame(final String payload) extends XiangqiFrame;

/// An Engine.IO `3` pong.
final class const XiangqiPongFrame(final String payload) extends XiangqiFrame;

/// A Socket.IO `0` CONNECT: the server accepted the namespace.
final class const XiangqiConnectFrame(final String? namespace, final Object? data)
    extends XiangqiFrame;

/// A Socket.IO `1` DISCONNECT.
final class const XiangqiDisconnectFrame(final String? namespace) extends XiangqiFrame;

/// A Socket.IO `4` CONNECT_ERROR.
final class const XiangqiConnectErrorFrame(final String? namespace, final Object? data)
    extends XiangqiFrame;

/// A Socket.IO `2` EVENT (or `5` BINARY_EVENT).
///
/// [data] is the frame's *second* array element and nothing else, which is what
/// [XiangqiSocketEvent.data] is too: every xiangqi.com event has exactly one payload.
final class const XiangqiEventFrame({
  required final String name,
  final Object? data,

  /// The ack id the sender asked to be answered on, or null if it did not.
  final int? ackId,

  /// Whether this came in as a `5` BINARY_EVENT.
  final bool binary = false,
}) extends XiangqiFrame;

/// A Socket.IO `3` ACK.
///
/// [args] is the frame's array as it stood: the arguments the server's callback was called with.
/// Every ack xiangqi.com sends carries one argument, an object — `[{"status":"OK"}]` for a move,
/// `{"event":"game.archived.get","status":"REDIRECT"}` for a `g_v2.get` on a finished game, `[]`
/// (no argument at all) for `g_v2.finish`. [XiangqiSocketClient.emit] hands back that first
/// argument and hides the list, because a caller who has to write `ack.first` every time will
/// eventually write it where there is no first.
final class const XiangqiAckFrame(final int ackId, final List<Object?> args) extends XiangqiFrame;

/// An event, ready to be read by the app: a name and its single payload.
@immutable
class const XiangqiSocketEvent({required final String name, final Object? data}) {
  @override
  String toString() => 'XiangqiSocketEvent($name, $data)';
}

/// Parses one raw websocket frame, whatever kind it is, or null if it is none of them.
///
/// The shape of the conversation, as captured from the live server:
/// * `0{...}`                                  Engine.IO open
/// * `2` / `2<payload>`                        Engine.IO ping (the server's heartbeat)
/// * `3` / `3<payload>`                        Engine.IO pong
/// * `40/xiangqi,{...}`                        Socket.IO CONNECT ack
/// * `44/xiangqi,{...}`                        Socket.IO CONNECT_ERROR
/// * `41/xiangqi,`                             Socket.IO DISCONNECT
/// * `42/xiangqi,["<event>",<payload>]`        an event
/// * `42/xiangqi,<ackid>["<event>",<payload>]` an event whose sender wants an ack
/// * `43/xiangqi,<ackid>[<payload>]`           an ack
///
/// and, from clients that connect without the Engine.IO prefix, the same socket.io packets bare:
/// `2["<event>",...]` and `2/xiangqi,[...]`.
///
/// The ambiguity worth naming: a leading `2` is an Engine.IO ping when what follows it is neither
/// `[` nor `/`, and a Socket.IO EVENT when it is. That is the rule the Rust side of this repo uses
/// too, and it is the one thing a naive "strip the first character" parser gets wrong.
XiangqiFrame? parseXiangqiFrame(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  var s = trimmed;

  // Engine.IO prefix: 0=open 1=close 2=ping 3=pong 4=message 5=upgrade.
  final first = s.codeUnitAt(0);
  if (_isDigit(first)) {
    final rest = s.substring(1);
    if (first == _cc4) {
      // "4" is a message: the socket.io packet follows it.
      s = rest;
    } else if (first == _cc2 && (rest.startsWith('[') || rest.startsWith('/'))) {
      // A bare socket.io EVENT, no Engine.IO prefix — "2[event,...]", "2/xiangqi,[event,...]".
    } else {
      return switch (first) {
        _cc0 => XiangqiOpenFrame(_jsonObjectOrEmpty(rest)),
        _cc2 => XiangqiPingFrame(rest),
        _cc3 => XiangqiPongFrame(rest),
        // 1 (close) and 5 (upgrade) carry nothing we act on; anything else is not a frame.
        _ => null,
      };
    }
  }

  if (s.isEmpty) return null;

  final type = s.codeUnitAt(0);
  var body = s.substring(1);

  String? namespace;
  if (body.startsWith('/')) {
    final comma = body.indexOf(',');
    if (comma == -1) return null;
    namespace = body.substring(0, comma);
    body = body.substring(comma + 1);
  }

  switch (type) {
    case _cc0:
      return XiangqiConnectFrame(namespace, _jsonOrNull(body));
    case _cc1:
      return XiangqiDisconnectFrame(namespace);
    case _cc2:
      final (ackId, rest) = _splitAckId(body);
      final array = _jsonArrayAt(rest);
      if (array == null || array.isEmpty || array.first is! String) return null;
      return XiangqiEventFrame(
        name: array.first! as String,
        data: array.length > 1 ? array[1] : null,
        ackId: ackId,
      );
    case _cc3:
      final (ackId, rest) = _splitAckId(body);
      if (ackId == null) return null;
      final array = _jsonArrayAt(rest);
      if (array == null) return null;
      return XiangqiAckFrame(ackId, array);
    case _cc4:
      return XiangqiConnectErrorFrame(namespace, _jsonOrNull(body));
    case _cc5:
      // A binary event: "<attachments>-<event array>". The attachments count is skipped by
      // looking for the array, as the Rust parser does; only the event name is read.
      final array = _jsonArrayAt(body);
      if (array == null || array.isEmpty || array.first is! String) return null;
      return XiangqiEventFrame(
        name: array.first! as String,
        data: array.length > 1 ? array[1] : null,
        binary: true,
      );
    default:
      return null;
  }
}

/// Parses [raw] as an event, or returns null if it is any other kind of frame.
///
/// The narrow reading of [parseXiangqiFrame], kept separate because it is the one the Rust
/// `socketio::parse_frame` implements and whose behaviour is pinned by tests ported one for one:
/// `0{...}`, `2`, `3`, `""` and `hello` are all null here even though several of them are perfectly
/// good frames.
XiangqiSocketEvent? parseXiangqiSocketEvent(String raw) {
  final frame = parseXiangqiFrame(raw);
  return frame is XiangqiEventFrame ? XiangqiSocketEvent(name: frame.name, data: frame.data) : null;
}

const int _cc0 = 0x30; // '0'
const int _cc1 = 0x31; // '1'
const int _cc2 = 0x32; // '2'
const int _cc3 = 0x33; // '3'
const int _cc4 = 0x34; // '4'
const int _cc5 = 0x35; // '5'

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

Duration? _millis(Object? value) => value is int ? Duration(milliseconds: value) : null;

/// Consumes the leading digits of [s] as an ack id, returning it and the rest.
(int?, String) _splitAckId(String s) {
  var i = 0;
  while (i < s.length && _isDigit(s.codeUnitAt(i))) {
    i++;
  }
  if (i == 0) return (null, s);
  final parsed = int.tryParse(s.substring(0, i));
  return (parsed, s.substring(i));
}

/// The JSON at the first `[` of [s], or null if there is no well-formed array there.
///
/// The closing bracket is found by matching, not by taking the last `]` or the first one: a payload
/// may contain either, in a string (`"a]b\"c"`) or nested (`{"y":[1,2]}`), and only a matcher that
/// tracks string state and escapes gets those right. Content after the closing bracket is ignored,
/// which is what makes a concatenated polling response parse into its first frame.
List<Object?>? _jsonArrayAt(String s) {
  final open = s.indexOf('[');
  if (open == -1) return null;
  final close = _findMatchingClose(s, open);
  if (close == null) return null;
  final decoded = _jsonOrNull(s.substring(open, close + 1));
  return decoded is List ? decoded.cast<Object?>() : null;
}

/// The JSON object at the start of [s], or null if it is not one.
Object? _jsonOrNull(String s) {
  if (s.isEmpty) return null;
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _jsonObjectOrEmpty(String s) {
  final decoded = _jsonOrNull(s);
  return decoded is Map ? decoded.cast<String, Object?>() : const {};
}

/// The index of the `]` matching the `[` at [open], or null if it never closes.
///
/// Escapes and string state are tracked so that brackets inside a JSON string do not count.
int? _findMatchingClose(String s, int open) {
  if (open >= s.length || s.codeUnitAt(open) != 0x5b) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = open; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5c) {
        escaped = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    switch (c) {
      case 0x22:
        inString = true;
      case 0x5b:
        depth++;
      case 0x5d:
        depth--;
        if (depth == 0) return i;
    }
  }
  return null;
}

/// The xiangqi.com realtime client.
///
/// Use it like this:
///
/// ```dart
/// final socket = ref.read(xiangqiSocketProvider);
/// socket.stream.listen((event) => switch (event.name) { ... });
/// await socket.connect();
/// final ack = await socket.emit('g_v2.get', data: {'game_id': id});
/// ```
///
/// Three things about this protocol are worth knowing before writing a caller.
///
/// **An ack is not an acceptance.** `g_v2.move` is acked `{"status":"OK"}` whether or not the move
/// was legal; a rejected move comes back as a full-state `game.error` resync and nothing else. The
/// only proof a move landed is a `game.move.success` (or, for the other side,
/// `game.move.opponent`) on [stream]. Treat the ack as "the server read the packet".
///
/// **A `g_v2.get` ack is sometimes a redirect, not a failure.** Ask for a game that has finished and
/// the ack is `{"event":"game.archived.get","status":"REDIRECT"}` — re-send the same request under
/// the event name it names, and *that* ack is `{"event":"game.get.success",...}`. Read the `event`
/// field and follow it; do not hardcode `game.archived.get`, and do not read a `REDIRECT` status as
/// an error.
///
/// **Two emits have no ack at all, and one must not be sent.** Private chat messages come back with
/// no ack, so [emitNoAck] is the only honest way to send one — awaiting an ack that will never
/// arrive just burns [ackTimeout]. And a guest must never emit `chat.agreement`: the server treats
/// agreeing to the guest terms as a privileged, once-per-account action.
///
/// A fourth, about reading state after the game: while spectating there is no reliable game-over
/// frame. A spectator can watch `game.move.opponent` and `game.server.end` go by and still never
/// be told the game ended — if the UI has to know, it has to ask.
class XiangqiSocketClient({
  required final WebSocketChannelFactory _channelFactory,
  required final Future<String?> Function() _getToken,
  final Stream<Object?>? sessionChanges,
  final Uri Function(String token)? uriBuilder,

  /// The Socket.IO namespace this client talks to.
  final String namespace = kXiangqiSocketNamespace,

  /// How long a connection attempt may take.
  final Duration connectTimeout = const Duration(seconds: 10),

  /// How long to wait for an ack before giving up on one.
  final Duration ackTimeout = const Duration(seconds: 10),

  /// The first delay before reconnecting, doubled on each further failure.
  final Duration reconnectDelay = const Duration(seconds: 1),

  /// The longest delay between reconnects.
  final Duration maxReconnectDelay = const Duration(seconds: 30),

  // Mutable, because the open frame replaces them with the heartbeat the server itself asks for.
  var Duration _pingInterval = kXiangqiDefaultPingInterval,
  var Duration _pingTimeout = kXiangqiDefaultPingTimeout,
}) {
  final Uri Function(String token) _uriBuilder = uriBuilder ?? xiangqiSocketUri;

  final _events = StreamController<XiangqiSocketEvent>.broadcast();
  final _connected = StreamController<void>.broadcast();
  final _statuses = StreamController<XiangqiConnectionStatus>.broadcast();
  StreamSubscription<Object?>? _identitySubscription;
  XiangqiConnectionStatus _status = XiangqiConnectionStatus.closed;
  int _attemptGeneration = 0;
  bool _gettingToken = false;

  XiangqiConnectionStatus get status => _status;
  Stream<XiangqiConnectionStatus> get statusStream => _statuses.stream;
  void _setStatus(XiangqiConnectionStatus status) {
    if (_status == status || _statuses.isClosed) return;
    _status = status;
    _statuses.add(status);
  }

  /// A separate transport and request/ack namespace, sharing only session acquisition.
  XiangqiSocketClient fork() => XiangqiSocketClient(
    channelFactory: _channelFactory,
    getToken: _getToken,
    sessionChanges: sessionChanges,
    uriBuilder: _uriBuilder,
    namespace: namespace,
    connectTimeout: connectTimeout,
    ackTimeout: ackTimeout,
  );
  final Completer<void> _firstConnection = Completer<void>();

  /// Acks still being waited on, by ack id.
  final Map<int, Completer<Object?>> _pendingAcks = {};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Completer<void>? _handshake;
  int _ackId = 0;
  int _reconnectAttempts = 0;
  bool _isConnected = false;
  bool _isDisposed = false;
  bool _manualClose = false;
  bool _wantsConnection = false;
  Future<void>? _connecting;

  /// The incoming events, one per `42` frame.
  Stream<XiangqiSocketEvent> get stream => _events.stream;

  /// Fires once per successful handshake, the first one included.
  Stream<void> get connectedStream => _connected.stream;

  /// Completes when the **first** handshake succeeds.
  ///
  /// Stays pending forever if the client is closed first; it is a one-shot, not a liveness signal.
  /// Use [connectedStream] to hear about later reconnects.
  Future<void> get firstConnection => _firstConnection.future;

  /// Whether the handshake is done and the channel is open.
  bool get isConnected => _isConnected;

  bool get isDisposed => _isDisposed;

  /// Opens the socket and completes when the handshake is done.
  ///
  /// Fails with [XiangqiSocketException] if there is no stored session, or if this attempt did not
  /// get as far as a CONNECT ack — a reconnect is scheduled behind it either way. Calling it again
  /// while an attempt is in flight returns that same attempt's future.
  Future<void> connect() {
    if (_isDisposed) {
      return Future.error(const XiangqiSocketException('This socket has been disposed.'));
    }
    _wantsConnection = true;
    if (_isConnected) return Future<void>.value();
    _identitySubscription ??= sessionChanges?.listen((session) {
      // Token creation/refresh while acquiring credentials belongs to this handshake.
      if (_gettingToken && session != null) return;
      final reconnect = _wantsConnection;
      final pending = _connecting;
      close();
      // Logout must not mint a guest behind the user's back. Remember active
      // consumers so a later explicit login can reopen their connection.
      _wantsConnection = reconnect;
      if (session != null && reconnect) {
        Future<void> reopen() async {
          try {
            await pending;
          } on Object {
            /* The old handshake was deliberately cancelled. */
          }
          if (!_isDisposed) await connect();
        }

        reopen().ignore();
      }
    });
    final existing = _connecting;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _connect().whenComplete(() {
      if (identical(_connecting, future)) _connecting = null;
    });
    _connecting = future;
    return future;
  }

  Future<void> _connect() async {
    _manualClose = false;
    _setStatus(XiangqiConnectionStatus.connecting);
    final generation = ++_attemptGeneration;
    final String? token;
    _gettingToken = true;
    try {
      token = await _getToken();
    } on Object {
      _scheduleReconnect();
      rethrow;
    } finally {
      _gettingToken = false;
    }
    if (_isDisposed || generation != _attemptGeneration) {
      throw const XiangqiSocketException('Connection attempt cancelled.');
    }
    if (token == null || token.isEmpty) {
      throw const XiangqiSocketException('No xiangqi.com session to connect with.');
    }

    final channel = await _openChannel(_uriBuilder(token), token);
    if (_isDisposed || generation != _attemptGeneration) {
      await channel.sink.close();
      throw const XiangqiSocketException('Connection attempt cancelled.');
    }

    _channel = channel;
    final handshake = Completer<void>()..future.ignore();
    _handshake = handshake;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object error) => _failOnAttempt('socket error: ${_redact('$error', token ?? '')}'),
      onDone: () => _failOnAttempt('socket closed'),
      cancelOnError: false,
    );

    // The server pings every _pingInterval and drops us if no pong comes back within
    // _pingTimeout; the same pair, from our side, is how long we wait to hear from it at all.
    _restartPingWatchdog();

    _send('40$namespace,${jsonEncode({'token': token})}');
    try {
      await handshake.future.timeout(connectTimeout);
    } on TimeoutException {
      _failOnAttempt('namespace handshake timed out');
      rethrow;
    }
  }

  /// Opens the channel, with the token taken out of whatever the failure says.
  ///
  /// The reason this is not a one-liner: a real websocket failure reports the URL it failed to
  /// reach, and ours carries the session token. Rethrowing a redacted message is the only way to
  /// keep the token out of a crash report.
  Future<WebSocketChannel> _openChannel(Uri url, String token) async {
    try {
      return await _channelFactory.create(url.toString(), timeout: connectTimeout);
    } catch (e) {
      _scheduleReconnect();
      throw XiangqiSocketException(_redact('could not reach $url: $e', token));
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final frame = parseXiangqiFrame(raw);
    switch (frame) {
      case final XiangqiOpenFrame f:
        _pingInterval = f.pingInterval ?? _pingInterval;
        _pingTimeout = f.pingTimeout ?? _pingTimeout;
      case final XiangqiConnectFrame f:
        if (f.namespace == null || f.namespace == namespace) _onConnected();
      case final XiangqiConnectErrorFrame f:
        if (f.namespace == null || f.namespace == namespace) {
          _failOnAttempt('the server refused the connection: ${f.data}');
        }
      case final XiangqiPingFrame f:
        _send('3${f.payload}');
        _restartPingWatchdog();
      case XiangqiPongFrame():
        // We never ping, so a pong is unexpected; ignore it rather than treat it as a signal.
        break;
      case final XiangqiEventFrame f:
        if (!_events.isClosed) {
          _events.add(XiangqiSocketEvent(name: f.name, data: f.data));
        }
      case final XiangqiAckFrame f:
        final completer = _pendingAcks.remove(f.ackId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(f.args.isEmpty ? null : f.args.first);
        }
      case XiangqiDisconnectFrame():
        _failOnAttempt('the server disconnected the namespace');
      case null:
        break;
    }
  }

  void _onConnected() {
    _isConnected = true;
    _setStatus(XiangqiConnectionStatus.connected);
    _reconnectAttempts = 0;
    if (!_firstConnection.isCompleted) _firstConnection.complete();
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) handshake.complete();
    if (!_connected.isClosed) _connected.add(null);
  }

  /// Fails the in-flight connection attempt, if there is one, and starts over.
  void _failOnAttempt(String reason) {
    if (_isDisposed || _manualClose) return;
    _logger.warning('xiangqi.com socket: $reason');
    final handshake = _handshake;
    _handshake = null;
    _teardown();
    _scheduleReconnect();
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(XiangqiSocketException(reason));
    }
  }

  void _restartPingWatchdog() {
    _pingTimer?.cancel();
    _pingTimer = Timer(_pingInterval + _pingTimeout, () {
      _failOnAttempt('no ping from the server within ${_pingInterval + _pingTimeout}');
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed || _manualClose) return;
    _setStatus(XiangqiConnectionStatus.reconnecting);
    final delay = _backoff();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_isDisposed || _manualClose) return;
      connect().ignore();
    });
  }

  Duration _backoff() {
    final attempt = _reconnectAttempts++;
    final shift = attempt > 16 ? 16 : attempt;
    final millis = reconnectDelay.inMilliseconds * (1 << shift);
    return millis >= maxReconnectDelay.inMilliseconds
        ? maxReconnectDelay
        : Duration(milliseconds: millis);
  }

  /// Drops the current connection without deciding anything about reconnecting.
  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    _isConnected = false;
    if (channel != null) {
      channel.sink.close().catchError((Object _) {});
    }
    final pending = _pendingAcks.values.toList();
    _pendingAcks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(
          const XiangqiSocketException('The connection dropped before the ack arrived.'),
        );
      }
    }
  }

  /// Sends one raw frame.
  void _send(String raw) {
    final channel = _channel;
    if (channel == null) {
      throw const XiangqiSocketException('The xiangqi.com socket is not connected.');
    }
    channel.sink.add(raw);
  }

  /// Emits [event] and completes with the ack's argument.
  ///
  /// The ack id is the correlation handle: it is handed out here, put in the frame, and used to
  /// match the `43` that comes back, so two emits in flight at once cannot be confused.
  ///
  /// Throws [TimeoutException] if no ack arrives within [timeout] (or [ackTimeout]), and
  /// [XiangqiSocketException] if the socket is not connected or drops first.
  ///
  /// Do not use this for private chat: those emits are never acked. And never for `chat.agreement`
  /// as a guest — see the class doc.
  Future<Object?> emit(String event, {Object? data, Duration? timeout}) async {
    if (!_isConnected) {
      throw const XiangqiSocketException('The xiangqi.com socket is not connected.');
    }
    final ackId = ++_ackId;
    final completer = Completer<Object?>();
    _pendingAcks[ackId] = completer;
    try {
      _send('42$namespace,$ackId${jsonEncode([event, ?data])}');
      return await completer.future.timeout(timeout ?? ackTimeout);
    } finally {
      _pendingAcks.remove(ackId);
    }
  }

  /// Emits [event] without asking for an ack.
  ///
  /// The right call for private chat, which is never acked, and for anything fired while the
  /// response is being watched for on [stream] instead.
  void emitNoAck(String event, {Object? data}) {
    _send('42$namespace,${jsonEncode([event, ?data])}');
  }

  /// Closes the connection. The client can be connected again afterwards.
  void close() {
    _manualClose = true;
    _wantsConnection = false;
    _attemptGeneration++;
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(const XiangqiSocketException('Connection closed.'));
    }
    _handshake = null;
    _teardown();
    _setStatus(XiangqiConnectionStatus.closed);
  }

  /// Closes the connection and the streams. The client cannot be used again.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    close();
    await _identitySubscription?.cancel();
    await _events.close();
    await _connected.close();
    await _statuses.close();
  }
}

/// Takes the session token out of [message].
///
/// Two passes, because a URL reaches a message in two shapes: with the token as a bare substring
/// (an exception that echoes the value) and with it still spelled `jwt=...` inside a query string.
String _redact(String message, String token) {
  var redacted = message;
  if (token.isNotEmpty) {
    redacted = redacted.replaceAll(token, '<redacted-jwt>');
  }
  return redacted.replaceAll(RegExp(r'''jwt=[^&\s'"]*'''), 'jwt=<redacted-jwt>');
}

/// The xiangqi.com socket, one per app, kept alive for as long as the provider is.
///
/// The connection is **not** opened here: call [XiangqiSocketClient.connect] from the screen that
/// needs it, so that opening a xiangqi game is what puts a xiangqi socket on the wire — and so that
/// nothing at app start touches a second server.
///
/// ## The token, and the guest session behind it
///
/// **The socket refuses a connection with no token at all** — measured on 2026-10-16, where a join
/// with no `jwt` was answered `44/xiangqi,{"message":"Connection rejected by server"}`. So a device
/// that has never signed in cannot open one, and the two things that live on the socket — watching
/// a game and reading one back — would be unavailable to it.
///
/// What makes them available is the guest session the site's own client mints for a visitor:
/// `POST /api/users/guest_jwt` answers a token that the socket accepts, and a guest was measured
/// being handed a live game's snapshot and a whole archived game's analysis. So the token is read
/// from storage, and **minted on demand** when there is none.
///
/// On demand and not at startup, deliberately: minting one is an account on somebody else's service,
/// and a reader who never opens a xiangqi screen should not have one made for them. The moment the
/// socket is asked to connect is the moment the app has a reason.
///
/// The subscription is not decoration. [XiangqiAuthController] is `autoDispose`, so it is collected
/// between the read that finds no session and the write that stores the guest one unless something
/// is listening to it — and a controller collected mid-flight is a guest token that never lands.
final xiangqiSocketProvider = Provider<XiangqiSocketClient>((Ref ref) {
  final sessions = ref.read(xiangqiSessionStoreProvider);
  final auth = ref.read(xiangqiAuthControllerProvider.notifier);

  // Held for the provider's own lifetime, which is the app's: see the class doc.
  final keepAlive = ref.listen(xiangqiAuthControllerProvider, (_, _) {});
  ref.onDispose(keepAlive.close);

  final client = XiangqiSocketClient(
    sessionChanges: sessions.changes
        .map((s) => s == null ? null : (s.userId, s.accessToken))
        .distinct(),
    channelFactory: ref.read(webSocketChannelFactoryProvider),
    getToken: () async {
      final stored = await sessions.read();
      if (stored != null) return await ref.read(xiangqiClientProvider).socketToken();
      try {
        await auth.ensureGuestSession();
      } on Object catch (error, stackTrace) {
        // The socket reports the failure that follows; this is the reason behind it, which the
        // socket's own message cannot carry.
        _logger.warning('Could not mint a guest xiangqi.com session.', error, stackTrace);
        return null;
      }
      return (await sessions.read())?.accessToken;
    },
  );
  ref.onDispose(client.dispose);
  return client;
}, name: 'XiangqiSocketProvider');

enum XiangqiConnectionStatus() {
  connecting,
  connected,
  reconnecting,
  closed,
}

/// Replies without game ids are safe only inside their own transport lifetime.
final xiangqiGameSocketProvider = Provider.autoDispose.family<XiangqiSocketClient, String>((
  ref,
  gameId,
) {
  final client = ref.read(xiangqiSocketProvider).fork();
  ref.onDispose(client.dispose);
  return client;
}, name: 'XiangqiGameSocketProvider');

final xiangqiReviewSocketProvider = Provider.autoDispose.family<XiangqiSocketClient, String>((
  ref,
  gameId,
) {
  final client = ref.read(xiangqiSocketProvider).fork();
  ref.onDispose(client.dispose);
  return client;
}, name: 'XiangqiReviewSocketProvider');
