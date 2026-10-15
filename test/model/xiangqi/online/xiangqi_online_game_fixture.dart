// The frame shapes below are the ones the 2026-10-13 probe measured against xiangqi.com (FACTS.md),
// but the sequence built out of them is constructed: it is not a replay of a captured game, because
// that probe's game never got a single legal move onto the board. What is real here is the envelope
// of each frame — `game.get.success` at the top level, `game.move.*` and `game.server.end` under
// their own `data`, the `timers` object, `end_reason`/`end_result` — and what is invented is every
// number inside it: the players, the ratings, the clocks, and the game itself.
//
// Everything about the *position* is not invented. The moves are played through the repo's own rules
// engine to build the expected positions and the `fen` fields, so the tests below check the
// controller's reading of the wire against the rules engine rather than against a string written out
// here. A move in this file that the rules reject throws when the file is loaded, which is the
// fixture checking itself before any test runs.
//
// The transport is a fake `WebSocketChannel` of the shape `test/network/xiangqi_socket_test.dart`
// uses — deliberately not the repo's `test/network/fake_websocket_channel.dart`, which runs
// `jsonDecode` on every outgoing frame with no try/catch and so throws on the first `40/xiangqi,...`
// the client writes. What is added here is the ack: this fixture answers an emit the way the server
// does, so a test drives the game rather than the socket.

import 'dart:async';
import 'dart:convert';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_online_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/socket.dart' show WebSocketChannelFactory;
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show XiangqiAuthStorage;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The id of the game every frame here belongs to.
const xiangqiTestGameId = 'GbXk2mQp';

/// The account this device plays as — a guest, whose token's `sub` is a string.
const xiangqiTestViewerId = 'guest7zuq8';

/// The guest who is watching, and who is therefore in neither seat.
const xiangqiTestSpectatorId = 'guestzzzzz';

/// The ids of the two seats. Red is this device; black is the other player.
const xiangqiTestRedId = xiangqiTestViewerId;
const xiangqiTestBlackId = '100001';

/// The names and ratings the snapshot reports. Red is a guest and has no rating, which is also what
/// the snapshot for a guest seat really looks like.
const xiangqiTestRedName = 'guest7zuq8';
const xiangqiTestBlackName = 'Maestro';

/// The rating the black seat carries.
const xiangqiTestBlackRating = 2011;

/// The game, in xiangqi.com's own rank-1 UCI, in the order it was played.
///
/// Red's cannon opens the file, black's horse comes out, red's horse comes out, black's other horse
/// comes out, and red's rook takes the file its own horse vacated. The second entry is the one that
/// matters most: `h10g8` is a rank-ten square, spelled in the one notation in this protocol that is
/// not the repo's.
const xiangqiTestMoveUcis = ['h3e3', 'h10g8', 'h1g3', 'b10c8', 'i1h1'];

/// The moves of [xiangqiTestMoveUcis], as moves.
final xiangqiTestMoves = IList([for (final uci in xiangqiTestMoveUcis) _moveOf(uci)]);

/// Every position of the game, the initial one first.
///
/// Played through [rules.play], and not caught: this is the oracle the controller's own replay is
/// checked against, so a move that does not play is a mistake in this file and should be loud.
final xiangqiTestPositions = _replay(xiangqiTestMoves);

/// The instant the server's clocks are stamped with: the moment this file was loaded.
///
/// A stamp only has to be *an* instant — the state counts from it and nothing else — and taking the
/// wall clock rather than a fixed number means a screen that draws the clocks draws a plausible
/// reading, instead of a game that ran out of time a year ago.
final xiangqiTestServerClock = DateTime.now().millisecondsSinceEpoch;

/// The instant [seconds] after the frame that stamped the clocks.
///
/// What a caller passes as "now" to count a clock with: the reading at the stamp, less the time since.
DateTime xiangqiTestClockAfter(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(xiangqiTestServerClock + seconds * 1000);

/// What the server says [side] has left after [plies] plies.
///
/// Made up, like every number here: the probe's own game never moved, so its readings are the one
/// thing about its clocks nobody can check. Ten minutes a side, twenty seconds a red move and
/// twenty-five a black one — the shape of a real game without the claim of being one.
int xiangqiTestSecondsLeft(XiangqiSide side, int plies) {
  final moves = side == XiangqiSide.red ? (plies + 1) ~/ 2 : plies ~/ 2;
  return 600 - moves * (side == XiangqiSide.red ? 20 : 25);
}

/// The `timers` object of a frame after [plies] plies.
///
/// `move_secs` is the per-move allowance and is not read by anything here — it is in the probe's
/// frames and is kept so that the shape is the measured one.
Map<String, Object?> xiangqiTestTimers(int plies) => {
  'red': {'game_secs': xiangqiTestSecondsLeft(XiangqiSide.red, plies), 'move_secs': 120},
  'black': {'game_secs': xiangqiTestSecondsLeft(XiangqiSide.black, plies), 'move_secs': 120},
  'server_clock': xiangqiTestServerClock,
};

/// One `move_history` record, `"c3d5 577/120 570/120 3"`, of the move played at [ply] (1-based).
///
/// Only the leading token of a record is the move: the other three fields are the clocks and the time
/// that move took, and this client reads neither of them, because the frame's own `timers` object
/// carries the clocks.
String xiangqiTestMoveRecord(int ply) {
  final before = ply - 1;
  return '${xiangqiTestMoveUcis[before]} '
      '${xiangqiTestSecondsLeft(XiangqiSide.red, before)}/120 '
      '${xiangqiTestSecondsLeft(XiangqiSide.black, before)}/120 ${2 + before}';
}

/// The `move_history` entries of a snapshot carrying the first [plies] moves.
List<String> xiangqiTestMoveHistory(int plies) => [
  for (var ply = 1; ply <= plies; ply++) xiangqiTestMoveRecord(ply),
];

/// A raw `42` frame carrying [event] and [payload], which is how the server writes one.
String xiangqiEventFrame(String event, Object? payload) =>
    '42/xiangqi,${jsonEncode([event, payload])}';

/// The payload of a snapshot of the game after the first [plies] moves.
///
/// The snapshot is the one frame envelope that does **not** nest what it has to say under `data`:
/// everything is at the top level. Its `fen` is the rules engine's own for the position those moves
/// make, though nothing here reads it — the moves are the game, and this client replays them.
///
/// [ended] adds the result the way an archived snapshot carries one — the same `end_reason` and
/// `end_result` a `game.server.end` frame has, which is the only way a spectator ever learns how the
/// game ended.
Map<String, Object?> xiangqiSnapshotPayload({int plies = 0, bool ended = false}) => {
  'id': xiangqiTestGameId,
  'is_rated': true,
  'fen': xiangqiTestPositions[plies].toFen(),
  'rplayer': {'id': xiangqiTestRedId, 'username': xiangqiTestRedName},
  'bplayer': {
    'id': xiangqiTestBlackId,
    'username': xiangqiTestBlackName,
    'rating': xiangqiTestBlackRating,
  },
  'move_history': xiangqiTestMoveHistory(plies),
  'timers': xiangqiTestTimers(plies),
  if (ended) ...xiangqiTestResult,
};

/// A `game.get.success` snapshot of the game after the first [plies] moves.
///
/// The payload is at the top level of the frame, which is the shape this file has always built and
/// which [XiangqiOnlineGameController] reads. It is **not** the shape the server was measured
/// sending — see [xiangqiNestedSnapshotFrame], which is, and which the controller also reads. Both
/// are kept because both are handled, and a test that only ever sent one of them would leave the
/// other path unexercised.
String xiangqiSnapshotFrame({int plies = 0, bool ended = false}) =>
    xiangqiEventFrame('game.get.success', xiangqiSnapshotPayload(plies: plies, ended: ended));

/// The same snapshot, nested under `data` — the shape `game.get.success` really arrives in.
///
/// Measured on 2026-10-15 against a signed-in account and a game of its own: the frame is
/// `42/xiangqi,["game.get.success",{"data":{...}}]`, with the whole snapshot one level down. Every
/// other frame this file builds is nested that way already (`game.move.*` and `game.server.end`
/// both carry `data`), so the top-level form above is the odd one out and this is the one the
/// server sends.
String xiangqiNestedSnapshotFrame({int plies = 0, bool ended = false}) => xiangqiEventFrame(
  'game.get.success',
  {'data': xiangqiSnapshotPayload(plies: plies, ended: ended)},
);

/// The same snapshot under the name a *finished* game is asked for.
///
/// A `g_v2.get` for a game that is over is answered with a redirect rather than an error, and the
/// snapshot is not on `game.get.success` but on the event the ack names, suffixed `.success`. See
/// [xiangqiRedirectAck], which is what makes the controller ask for it.
String xiangqiArchivedSnapshotFrame({bool ended = true}) => xiangqiEventFrame(
  'game.archived.get.success',
  xiangqiSnapshotPayload(plies: xiangqiTestMoveUcis.length, ended: ended),
);

/// The `game.move.success` / `game.move.opponent` frame that carries the [ply]-th move (1-based).
///
/// One shape for both, which is what the server sends: `game.move.success` is this device's own move
/// and `game.move.opponent` is the other side's, and which one it is says only who made the move.
/// Red moves on odd plies here, and red is the seat this device holds, so odd plies are `success`.
///
/// The `move` is a whole record rather than the bare UCI: the move is its first token and the rest is
/// clocks this client reads from `timers` instead. The `fen` is the rules engine's position after the
/// move — which this client does not read either, since it replays the move onto the position it
/// already has, but which is what the server would be sending.
String xiangqiMoveFrame(int ply) =>
    xiangqiEventFrame(ply.isOdd ? 'game.move.success' : 'game.move.opponent', {
      'type': 'move',
      'data': {
        'move': xiangqiTestMoveRecord(ply),
        'fen': xiangqiTestPositions[ply].toFen(),
        'turn_now': xiangqiTestPositions[ply].turn.name,
        'moves_count': ply,
        'timers': xiangqiTestTimers(ply),
      },
    });

/// The `game.server.end` frame of a game black resigned.
///
/// `end_result` is the only place the loser is written down: there is no winner field, only the pair
/// of `{factor, result}` objects the live capture showed, in which the side that won reads
/// `result: 30` and the side that lost `result: 10`. The factors are the rating change.
String xiangqiEndFrame() =>
    xiangqiEventFrame('game.server.end', {'type': 'end', 'data': xiangqiTestResult});

/// The two fields that say how a game ended: the code, and who lost.
///
/// Red won and black lost, so red is the side with `result: 30`. The sign of `factor` is the rating
/// change the capture showed — the winner's positive.
const Map<String, Object?> xiangqiTestResult = {
  'end_reason': kXiangqiComEndResign,
  'end_result': {
    'red': {'factor': 20, 'result': kXiangqiComResultWin},
    'black': {'factor': -20, 'result': kXiangqiComResultLoss},
  },
};

/// The ack that turns a `g_v2.get` into a request for the archived snapshot instead.
///
/// The real answer for a game that has finished: the client is told to say the same thing again under
/// another name, and the name is the server's to choose. Put it in
/// [FakeXiangqiChannel.ackOverrides] under `g_v2.get`.
const Map<String, Object?> xiangqiRedirectAck = {
  'event': 'game.archived.get',
  'status': 'REDIRECT',
};

/// The token of an account with the given subject, written the way xiangqi.com writes one.
///
/// A real JWT and a real base64url payload segment, with the signature left as a made-up string: the
/// only thing read from it here is the `sub`, and it is read without checking the signature, because
/// a token this device was handed over TLS by the service it is talking to is not a trust boundary.
String xiangqiTestToken(String subject) =>
    'eyJhbGciOiJIUzI1NiJ9.'
    '${base64Url.encode(utf8.encode(jsonEncode({'sub': subject}))).replaceAll('=', '')}'
    '.not-a-real-signature';

/// A session holding [token], for a fake storage to hand out.
XiangqiSession xiangqiTestSession(String token, {String userId = xiangqiTestViewerId}) =>
    XiangqiSession(userId: userId, name: userId, accessToken: token, isGuest: true);

/// A [XiangqiAuthStorage] with no disk behind it.
///
/// The controller reads the token itself rather than asking the auth controller, so the whole of what
/// a test has to provide is the string that would have come off the disk.
class FakeXiangqiAuthStorage(final XiangqiSession? session) extends XiangqiAuthStorage {
  /// Every session written through this storage.
  final List<XiangqiSession> writes = [];

  @override
  Future<XiangqiSession?> read() async => session;

  @override
  Future<void> write(XiangqiSession session) async => writes.add(session);

  @override
  Future<void> delete() async {}
}

/// The server's open frame, announcing the heartbeat the client should use.
const openFrame =
    '0{"sid":"s1","upgrades":[],"pingInterval":8000,"pingTimeout":20000,"maxPayload":1000000}';

/// The connect ack for the `/xiangqi` namespace.
const connectAckFrame = '40/xiangqi,{"sid":"s1"}';

/// The frame prefix an emit with an ack id starts with: `42/xiangqi,<id>[`.
final _emitPrefix = RegExp(r'^42/xiangqi,(\d+)(\[.*\])$');

/// A `WebSocketChannel` that carries raw text frames, records what was written to it, and answers.
class FakeXiangqiChannel() implements WebSocketChannel {
  /// Every frame the client wrote, in order.
  final List<Object?> sent = [];

  /// The ack to answer an event with, instead of `{"status":"OK"}`.
  ///
  /// The server acks `g_v2.get` with `{"status":"OK"}` for a game that is still on and with
  /// [xiangqiRedirectAck] for one that has finished, and which of the two it is is the only way a
  /// test asks for the archived snapshot.
  final Map<String, Object?> ackOverrides = {};

  /// Whether emits are answered at all.
  bool autoAck = true;

  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();

  late final WebSocketSink _sink = _FakeXiangqiSink(this);

  /// Whether the client asked for the channel to be closed.
  bool closed = false;

  /// Pushes one raw frame from the server.
  void fromServer(dynamic data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// Drops the connection the way a peer hanging up does.
  void closeFromServer([Object? error]) {
    if (_incoming.isClosed) return;
    if (error != null) _incoming.addError(error);
    _incoming.close();
  }

  /// Answers the emit [frame] carries, if it is one, the way the server answers one.
  ///
  /// The ack goes in as a microtask rather than synchronously: the client registers the ack id before
  /// it writes the frame, but nothing about a real ack is instant, and a test that pushes frames
  /// around this one should not have to know which of the two it is looking at.
  void answer(String frame) {
    if (!autoAck) return;
    final match = _emitPrefix.firstMatch(frame);
    if (match == null) return;
    final Object? args;
    try {
      args = jsonDecode(match.group(2)!);
    } catch (_) {
      return;
    }
    if (args is! List || args.isEmpty || args.first is! String) return;
    final ack = ackOverrides[args.first] ?? const {'status': 'OK'};
    final ackId = match.group(1)!;
    scheduleMicrotask(() {
      // The ack payload is the array of the callback's arguments, so `jsonEncode([ack])` is the
      // whole bracket run: an extra pair around it would nest the map one deep and hand the caller a
      // list where it is reading for a map — which is exactly what `emit` reads it for.
      if (!_incoming.isClosed) _incoming.add('43/xiangqi,$ackId${jsonEncode([ack])}');
    });
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => closed ? 1000 : null;

  @override
  String? get closeReason => closed ? 'OK' : null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  // The StreamChannel surface the socket client never touches.
  @override
  void pipe(StreamChannel<dynamic> other) {}

  @override
  StreamChannel<S> cast<S>() => throw UnimplementedError();

  @override
  StreamChannel<dynamic> changeSink(StreamSink<dynamic> Function(StreamSink<dynamic>) change) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> changeStream(Stream<dynamic> Function(Stream<dynamic>) change) =>
      throw UnimplementedError();

  @override
  StreamChannel<S> transform<S>(StreamChannelTransformer<S, dynamic> transformer) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> transformSink(StreamSinkTransformer<dynamic, dynamic> transformer) =>
      throw UnimplementedError();

  @override
  StreamChannel<dynamic> transformStream(StreamTransformer<dynamic, dynamic> transformer) =>
      throw UnimplementedError();
}

class _FakeXiangqiSink(final FakeXiangqiChannel _channel) implements WebSocketSink {
  @override
  void add(dynamic data) {
    _channel.sent.add(data);
    if (data is String) _channel.answer(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
  }

  @override
  Future<dynamic> get done => Future<void>.value();
}

/// Hands out [FakeXiangqiChannel]s and keeps them, so a test can drive the server's side.
class FakeXiangqiChannelFactory() implements WebSocketChannelFactory {
  final List<FakeXiangqiChannel> channels = [];
  final List<String> urls = [];

  /// The channel the client is talking on, once there is one.
  FakeXiangqiChannel get channel => channels.last;

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    urls.add(url);
    final channel = FakeXiangqiChannel();
    channels.add(channel);
    return channel;
  }
}

/// The moves named by [ucis].
XiangqiMove _moveOf(String uci) {
  final move = xiangqiMoveFromComUci(uci);
  if (move == null) throw ArgumentError('Not a xiangqi.com move: $uci');
  return move;
}

/// [moves] played out from the starting position, the initial position first.
IList<XiangqiPosition> _replay(IList<XiangqiMove> moves) {
  final positions = <XiangqiPosition>[XiangqiPosition.initial()];
  var position = positions.first;
  for (final move in moves) {
    position = rules.play(position, move);
    positions.add(position);
  }
  return positions.lock;
}
