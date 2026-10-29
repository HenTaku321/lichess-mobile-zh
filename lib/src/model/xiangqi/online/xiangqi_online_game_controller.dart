import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart' show XiangqiGameEnd;
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_premove.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:logging/logging.dart';

part 'xiangqi_online_game_controller.freezed.dart';

final _logger = Logger('XiangqiOnlineGame');

/// The event a client sends to be given a game: a full snapshot, once.
const String kXiangqiGetEvent = 'g_v2.get';

/// The event a client sends to play a move.
const String kXiangqiMoveEvent = 'g_v2.move';

/// The event a client sends to end the game, which in this app means resigning.
const String kXiangqiFinishEvent = 'g_v2.finish';

/// xiangqi.com's own end-reason codes, as `game.server.end` writes them.
///
/// Every code here was read off the server (a resign), or off the shipped bundle; the ones with no
/// evidence behind them are the ones this file deliberately does not act on — see [_endOf].
const int kXiangqiComEndCheckmate = 100;
const int kXiangqiComEndStalemate = 101;
const int kXiangqiComEndTimerExpired = 200;
const int kXiangqiComEndDisconnectTimerExpired = 201;
const int kXiangqiComEndResign = 300;
const int kXiangqiComEndDraw = 400;
const int kXiangqiComEndDrawNoCapture = 401;
const int kXiangqiComEndDrawNoThreatPattern = 402;
const int kXiangqiComEndDisconnect = 500;
const int kXiangqiComEndAbandon = 600;

/// The two `result` values of the `end_result` object, which is where the loser is actually named.
///
/// `game.server.end` carries no winner field, only a per-side `{factor, result}` pair, and the pair
/// that was captured live reads `{"red":{"factor":-20,"result":10},"black":{"factor":20,"result":30}}`
/// for a game red resigned. So `result` is 30 for the winner and 10 for the loser, and the loser is
/// the side the sentences need: "Black resigned", not "the game was resigned".
const int kXiangqiComResultWin = 30;
const int kXiangqiComResultLoss = 10;

/// What `state.error` holds when the socket is the thing that failed.
///
/// Not translated: it is a diagnostic, not a sentence the app promises. A wrong password has a
/// translation because the user can act on it; "the socket is down" has nothing to act on but the
/// network.
const String kXiangqiOnlineConnectionFailed = 'Lost the connection to xiangqi.com.';

/// What `state.error` holds when the server sent something this client could not read.
const String kXiangqiOnlineUnreadableGame = 'xiangqi.com sent a game this app could not read.';

/// How a game ended, and the side the outcome has to name.
///
/// A record rather than three fields of the state, because it is one answer: a resignation without
/// the side that resigned is not half an answer, it is no answer at all — see [_endOf].
typedef XiangqiOnlineEnd = ({
  XiangqiGameEnd end,
  XiangqiSide? resignedBy,
  XiangqiSide? flaggedSide,
});

/// One of the two players of an online game: who they are and how strong they are.
///
/// [id] is the account id, and it is the whole of how "which side am I?" is answered: the server
/// names the two seats and the token names the client, and the two are compared as strings.
@freezed
sealed class const XiangqiOnlinePlayer._() with _$XiangqiOnlinePlayer {
  const factory({
    /// The account's id. `''` for a seat nobody has taken yet.
    required String id,

    /// The name as the server spells it, or `''` before the seat is taken.
    required String name,

    /// The rating the server reports, or null when it reports none — a guest seat has none.
    int? rating,
  }) = _XiangqiOnlinePlayer;

  /// A seat nobody has taken.
  static const empty = XiangqiOnlinePlayer(id: '', name: '');

  /// Whether anybody is in this seat.
  bool get isTaken => id.isNotEmpty || name.isNotEmpty;
}

/// A game being played on xiangqi.com, as this client understands it right now.
///
/// Deliberately one shape for the two ways of looking at a game, playing it and watching it: the
/// screen is the same screen, and the only difference between the two is [mySide], which is null
/// when the seat nobody sitting here belongs to. Everything the board needs to be drawn and
/// everything the bottom bar needs to decide what to offer comes out of this one object.
@freezed
sealed class const XiangqiOnlineGameState._() with _$XiangqiOnlineGameState {
  const factory({
    /// Every position of the game, the initial one first, so `positions.length == moves.length + 1`
    /// — the invariant [xiangqiGameNotation] is built on.
    required IList<XiangqiPosition> positions,

    /// The moves that were played, in order.
    required IList<XiangqiMove> moves,

    /// The player of the red pieces.
    required XiangqiOnlinePlayer red,

    /// The player of the black pieces.
    required XiangqiOnlinePlayer black,

    /// Whether the game counts for rating. The snapshot's `is_rated`.
    @Default(false) bool isRated,

    /// The side this device plays, or null when it is only watching.
    ///
    /// Null covers two things on purpose: a spectator, who has no side, and the moment before the
    /// first snapshot, when nobody knows yet. [isLoaded] is what separates them.
    XiangqiSide? mySide,

    /// What red had left when [serverClock] was taken, or null when the game is untimed.
    int? redSeconds,

    /// What black had left when [serverClock] was taken, or null when the game is untimed.
    int? blackSeconds,

    /// The server's own clock at the moment of the last frame, in milliseconds since the epoch.
    ///
    /// This is the whole of how time is counted here: the server sends no tick, only this stamp and
    /// the two readings, so a clock that runs between frames has to be worked out from them — see
    /// [secondsLeftFor].
    int? serverClock,

    /// How the game ended, or null while it has not.
    XiangqiGameEnd? end,

    /// The side that gave up, when [end] is a resignation.
    XiangqiSide? resignedBy,

    /// The side that ran out of time, when [end] is a flag.
    XiangqiSide? flaggedSide,

    /// The piece the player has picked up, if any. Local to this client; the server knows nothing
    /// about it.
    XiangqiSquare? selected,

    /// Which position is being reviewed. `-1` follows the live end.
    @Default(-1) int cursor,

    /// Whether the socket is up, as far as this client can tell.
    ///
    /// Honest about being a guess: the client is never told when the connection drops, only when an
    /// attempt to use it fails, so a `true` here can be stale by as long as nothing has been sent.
    @Default(false) bool isConnected,

    /// Whether a snapshot has been read. Until it has, [mySide] is not "no side" but "not known".
    @Default(false) bool isLoaded,

    /// The last thing that went wrong, or null.
    ///
    /// **This can be set while [isLoaded] is false, and that pair is what a screen has to tell
    /// apart from "still loading".** A game that never arrived — the socket would not open, the
    /// server refused the namespace, the request was never answered — is a failure with nothing
    /// read, so `isLoaded` stays false and this carries the reason. A screen that checked
    /// `isLoaded` first would spin forever on it; see `XiangqiOnlineGameScreen._game`, which checks
    /// this first for exactly that reason.
    String? error,
  }) = _XiangqiOnlineGameState;

  /// The position the board is showing.
  XiangqiPosition get position => positions[viewCursor];

  /// The live end of the game.
  XiangqiPosition get gamePosition => positions.last;

  /// Which position the board is showing.
  int get viewCursor => cursor < 0 ? positions.length - 1 : cursor.clamp(0, positions.length - 1);

  bool get isAtLivePosition => viewCursor == positions.length - 1;

  /// The move that led to the position on the board.
  XiangqiMove? get lastMove => viewCursor == 0 ? null : moves[viewCursor - 1];

  /// The side to move in the live game.
  XiangqiSide get turn => gamePosition.turn;

  /// Whether the game is over.
  bool get isFinished => end != null;

  /// Whether this device is watching rather than playing, as far as it knows.
  bool get isSpectator => isLoaded && mySide == null;

  /// Whether it is this device's move and a move may be played.
  bool get isMyTurn =>
      isConnected && mySide != null && !isFinished && isAtLivePosition && turn == mySide;

  /// The side that won, or null for a draw — and for a game that has not ended.
  ///
  /// Mate and 困毙 are positions, so the loser is whoever is to move in them; a resignation and a
  /// flag are events, so the loser is the side the server named. The same split
  /// `xiangqi_game_controller.dart`'s own `winner` makes, for the same reason.
  XiangqiSide? get winner => switch (end) {
    .checkmate || .stalemate => turn.opposite,
    .resign => resignedBy?.opposite,
    .timeout => flaggedSide?.opposite,
    .threefoldRepetition || null => null,
  };

  /// The pieces [square] may be played to, or none when it holds nothing of the side to move.
  IList<XiangqiMove> get selectedMoves => selected == null || !isAtLivePosition
      ? const IListConst([])
      : turn == mySide
      ? rules.legalMovesFrom(gamePosition, selected!)
      : xiangqiPremovesFrom(gamePosition, selected!);

  /// How long [side] has left, counted from the last frame, or null when the game is untimed.
  ///
  /// The server sends no tick event: between two moves the only thing on the wire is the Engine.IO
  /// heartbeat, so a clock that only moved when a frame arrived would stand still for as long as
  /// the opponent thinks. What it does send is `timers.<side>.game_secs` — what that side had at
  /// `timers.server_clock` — and that is enough: the reading is that number minus the time since,
  /// and it is only subtracted for the side whose turn it is, because the other side's clock is
  /// stopped and its number stands.
  ///
  /// [now] is a parameter rather than a clock read so that the caller can drive it — the widget
  /// passes its own ticking `DateTime`, a test passes whatever it likes.
  int? secondsLeftFor(XiangqiSide side, DateTime now) {
    final atFrame = side == .red ? redSeconds : blackSeconds;
    if (atFrame == null) return null;
    final stamp = serverClock;
    if (stamp == null || isFinished || turn != side) return atFrame;
    final elapsed = now.millisecondsSinceEpoch - stamp;
    if (elapsed <= 0) return atFrame;
    final left = atFrame - elapsed ~/ 1000;
    return left < 0 ? 0 : left;
  }

  /// Keep the server's sub-second remainder for Clock's tenths display. The wire itself remains
  /// integer seconds; only elapsed wall time is subtracted here.
  Duration? timeLeftFor(XiangqiSide side, DateTime now) {
    final seconds = side == .red ? redSeconds : blackSeconds;
    if (seconds == null) return null;
    final atFrame = Duration(seconds: seconds);
    final stamp = serverClock;
    if (stamp == null || isFinished || turn != side) return atFrame;
    final elapsed = now.millisecondsSinceEpoch - stamp;
    if (elapsed <= 0) return atFrame;
    final left = atFrame - Duration(milliseconds: elapsed);
    return left < Duration.zero ? Duration.zero : left;
  }
}

/// A provider for the game with the given id: the id is the family argument, and it is xiangqi.com's
/// own game id, which is what every event of the conversation is addressed by.
///
/// `autoDispose` because a game is watched and then left: the socket subscription, the reconnect
/// and everything held here go away with the screen that needed them.
final xiangqiOnlineGameControllerProvider = AsyncNotifierProvider.autoDispose
    .family<XiangqiOnlineGameController, XiangqiOnlineGameState, String>(
      XiangqiOnlineGameController.new,
      name: 'XiangqiOnlineGameControllerProvider',
    );

typedef XiangqiQueuedPremove = ({XiangqiMove move, XiangqiPosition position});
typedef XiangqiConfirmedMove = ({
  XiangqiMove move,
  XiangqiPosition before,
  XiangqiPosition after,
  bool viaDragAndDrop,
});

/// Local, per-game state. Never serialised or forwarded to xiangqi.com as a premove packet.
final xiangqiPendingPremoveProvider = NotifierProvider.autoDispose
    .family<XiangqiPendingPremove, XiangqiQueuedPremove?, String>(
      XiangqiPendingPremove.new,
      name: 'XiangqiPendingPremoveProvider',
    );

class XiangqiPendingPremove(final String gameId) extends Notifier<XiangqiQueuedPremove?> {
  @override
  XiangqiQueuedPremove? build() => null;

  void queue(XiangqiQueuedPremove premove) {
    if (state != premove) state = premove;
  }

  void clear() => state = null;
}

/// One game on xiangqi.com, played or watched.
///
/// ## The wire, as this file understands it
///
/// Two directions, and they are spelt differently on purpose: `g_v2.*` is what the client sends and
/// `game.*` is what comes back, with `g_v2.get` answered by a `game.get.success` snapshot rather
/// than by its own ack.
///
/// The conversation, end to end:
/// * send `g_v2.get` with `{game_id}`. The ack is always `[{"status":"OK"}]`, whatever happened, so
///   it proves nothing about the game — the snapshot is the answer. For a game that is already over
///   the ack is `[{"event":"game.archived.get","status":"REDIRECT"}]` instead, which means "say it
///   again under this name"; the event in it is followed as it is written, never assumed.
/// * `game.get.success` — one full snapshot, once. It is the only place the players, the clocks and
///   the game's settings are named, and it carries the moves as `move_history`, each entry a string
///   whose first whitespace-separated token is the UCI in xiangqi.com's rank-1 spelling
///   (`"c3d5 577/120 570/120 3"`).
/// * `game.move.success` and `game.move.opponent` — one shape, one code path here: an own move and
///   an opponent's move differ only in who made it, and the position is replayed from both the same
///   way. `moves_count` is what keeps the two in order.
/// * `game.server.end` — the game is over. No winner field; the loser is in `end_result`.
/// * `game.error` — two different things under one name. With a `message` it is an error; without
///   one the frame *is* the game state, and the answer is to read it as a fresh snapshot.
///
/// ## What is deliberately not here
///
/// Draw offers, takebacks and increments are not implemented, and not because they were forgotten:
/// no evidence of their payloads exists — the one shape that was guessed (`{game_id, action}`) was
/// measured wrong — and a shape invented here would be a request the server silently drops. The
/// buttons are absent rather than disabled.
///
/// ## Resynchronising
///
/// A client that has lost the thread asks again: `resync()` sends `g_v2.get` and takes the snapshot
/// that comes back as the truth. It is called when the socket hands back a fresh connection (the
/// frames missed while it was down are not going to arrive), and after the game has ended, since a
/// spectator has no reliable game-over frame and the archived snapshot is what says what happened.
class XiangqiOnlineGameController(final String gameId)
    extends AsyncNotifier<XiangqiOnlineGameState> {
  int _snapshotRevision = 0;

  /// A snapshot explicitly supersedes pending incremental-move presentation, even if unchanged.
  int get snapshotRevision => _snapshotRevision;

  StreamSubscription<XiangqiSocketEvent>? _events;
  StreamSubscription<void>? _connections;
  StreamSubscription<XiangqiConnectionStatus>? _status;
  Timer? _moveConfirmation;
  Timer? _snapshotTimeout;
  int _buildGeneration = 0;
  bool _pendingMove = false;
  XiangqiMove? _submittedDragMove;

  /// Only confirmed incremental moves reach this stream; snapshots never produce feedback.
  final _confirmedMoves = StreamController<XiangqiConfirmedMove>.broadcast();
  Stream<XiangqiConfirmedMove> get confirmedMoves => _confirmedMoves.stream;
  bool get pendingMove => _pendingMove;
  bool _animateUpdate = false;
  bool get animateUpdate => _animateUpdate;

  /// The state as this controller last made it, readable before [build] has returned.
  late XiangqiOnlineGameState _latest;

  /// Whether [build] has returned. Writing `state` before it does is refused by Riverpod, and a
  /// frame can land while the first one is still being assembled.
  bool _built = false;

  /// The `sub` of the stored token: the id this device plays under, or null for no session.
  String? _userId;

  /// The event names whose arrival is a whole snapshot rather than a patch.
  final Set<String> _snapshotEvents = {'game.get.success'};

  /// Whether a `g_v2.get` is already on its way. Two of them would be two snapshots racing.
  bool _subscribing = false;

  /// When the side to move got the move, for the `thinking_time` a move is sent with.
  DateTime? _turnStartedAt;

  XiangqiSocketClient get _socket => ref.read(xiangqiGameSocketProvider(gameId));

  @override
  Future<XiangqiOnlineGameState> build() async {
    final generation = ++_buildGeneration;
    _built = false;
    _subscribing = false;
    _pendingMove = false;
    // Hold the per-game local state without rebuilding the network controller when it changes.
    ref.listen(xiangqiPendingPremoveProvider(gameId), (_, _) {});
    ref.onDispose(() {
      unawaited(_events?.cancel());
      _events = null;
      unawaited(_connections?.cancel());
      _connections = null;
      unawaited(_status?.cancel());
      _moveConfirmation?.cancel();
      _snapshotTimeout?.cancel();
      // Keep feedback through a retry rebuilding this notifier; close on final disposal.
      scheduleMicrotask(() {
        if (!ref.mounted && !_confirmedMoves.isClosed) unawaited(_confirmedMoves.close());
      });
    });
    final socket = ref.watch(xiangqiGameSocketProvider(gameId));
    // The token is read from storage, not from the auth controller — see [_userIdFromToken]. The
    // socket reads the same token for itself; the only thing this controller needs it for is the
    // subject, which is how "which of these two seats is mine?" gets an answer at all.
    final storage = ref.read(xiangqiSessionStoreProvider);
    String? token;
    try {
      token = (await storage.read())?.accessToken;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'The xiangqi.com session could not be read for game $gameId.',
        error,
        stackTrace,
      );
    }
    if (!ref.mounted || generation != _buildGeneration) throw StateError('Game load cancelled.');
    _userId = token == null ? null : _userIdFromToken(token);

    _latest = XiangqiOnlineGameState(
      positions: IList([XiangqiPosition.initial()]),
      moves: const IListConst([]),
      red: XiangqiOnlinePlayer.empty,
      black: XiangqiOnlinePlayer.empty,
    );
    _turnStartedAt = clock.now();

    _events = socket.stream.listen(_onEvent);
    _connections = socket.connectedStream.listen(_onConnected);
    _status = socket.statusStream.listen((status) {
      if (status != XiangqiConnectionStatus.connected) {
        _set(_latest.copyWith(isConnected: false, selected: null));
      }
    });

    // Connected after this build has returned, so that the snapshot the first frames bring cannot
    // be overwritten by the empty state this method is about to hand back.
    _built = true;
    unawaited(_connect(socket));
    return _latest;
  }

  /// Asks xiangqi.com for the game again and takes the answer as the truth.
  ///
  /// The way back from anything: a lost connection, a frame that could not be read, a spectator who
  /// was never told the game ended. Cheap enough to call from a screen that has just regained focus.
  Future<void> resync() => _subscribe();

  /// Plays [move] if it is this device's to play.
  ///
  /// The move is sent and **not** applied: the position only moves when the server echoes it back
  /// as `game.move.success`, so a move the server refuses — which it does silently, with an ack
  /// that says "OK" either way — never appears on the board.
  ///
  /// Returns whether anything was sent.
  Future<bool> playMove(XiangqiMove move, {bool viaDragAndDrop = false}) async {
    final state = _latest;
    if (!state.isMyTurn || !state.isConnected || _pendingMove || move.from == move.to) return false;
    if (!rules.isLegal(state.position, move)) return false;

    // `thinking_time` is seconds, not milliseconds — the probe sent milliseconds and the move was
    // dropped, and the field is read by the server as the number of seconds the player thought.
    final thought = clock.now().difference(_turnStartedAt ?? clock.now());
    final seconds = thought.inSeconds < 0 ? 0 : thought.inSeconds;
    final submittedPly = state.moves.length;
    _pendingMove = true;
    _submittedDragMove = viaDragAndDrop ? move : null;
    _moveConfirmation = Timer(const Duration(seconds: 10), () {
      _pendingMove = false;
      if (ref.mounted) unawaited(_subscribe());
    });
    try {
      await _socket.emit(
        kXiangqiMoveEvent,
        data: {'game_id': gameId, 'move': xiangqiMoveToComUci(move), 'thinking_time': seconds},
      );
      return true;
    } on Object catch (error, stackTrace) {
      // The confirmation event is authoritative even if its separate ack was
      // absent. Do not turn an already confirmed move into a connection error.
      if (_latest.moves.length > submittedPly && _latest.moves[submittedPly] == move) return true;
      _pendingMove = false;
      _moveConfirmation?.cancel();
      _logger.warning('Could not send a move for game $gameId.', error, stackTrace);
      _set(_latest.copyWith(error: kXiangqiOnlineConnectionFailed, isConnected: false));
      return false;
    }
  }

  /// Puts the board back on an earlier position in the recorded game.
  void goTo(int index, {bool fastSeek = false}) {
    cancelPremove();
    final clamped = index.clamp(0, _latest.positions.length - 1);
    _animateUpdate = !fastSeek && (clamped - _latest.viewCursor).abs() == 1;
    _set(_latest.copyWith(cursor: clamped, selected: null));
  }

  void goBackward() {
    if (_latest.viewCursor > 0) goTo(_latest.viewCursor - 1);
  }

  void goForward() {
    if (_latest.viewCursor < _latest.positions.length - 1) goTo(_latest.viewCursor + 1);
  }

  /// Picks up the piece on [square], or plays the picked-up piece onto it.
  ///
  /// The same two-taps-or-a-drag contract the offline screen's board has, kept here rather than in
  /// the widget because the selection is part of the state the board is drawn from.
  void clearSelection() => _set(_latest.copyWith(selected: null));

  void cancelPremove() {
    if (ref.mounted) ref.read(xiangqiPendingPremoveProvider(gameId).notifier).clear();
  }

  bool _canPremove(bool enabled) =>
      enabled &&
      _latest.isConnected &&
      _latest.mySide != null &&
      !_latest.isFinished &&
      _latest.isAtLivePosition &&
      _latest.turn != _latest.mySide &&
      !_pendingMove;

  void movePiece(XiangqiSquare from, XiangqiSquare to, {bool premoveEnabled = false}) {
    final move = XiangqiMove(from, to);
    if (_canPremove(premoveEnabled)) {
      if (_latest.position.pieceAt(from)?.side != _latest.mySide ||
          !xiangqiPremovesFrom(_latest.position, from).contains(move)) {
        return;
      }
      ref.read(xiangqiPendingPremoveProvider(gameId).notifier).queue((
        move: move,
        position: _latest.gamePosition,
      ));
      clearSelection();
      return;
    }
    if (!_latest.isMyTurn || _pendingMove || !rules.isLegal(_latest.gamePosition, move)) return;
    cancelPremove();
    clearSelection();
    unawaited(playMove(move, viaDragAndDrop: true));
  }

  void tapSquare(XiangqiSquare square, {bool premoveEnabled = false}) {
    final state = _latest;
    if ((!state.isMyTurn && !_canPremove(premoveEnabled)) || _pendingMove) return;

    final selected = state.selected;
    if (selected == null) {
      final queued = ref.read(xiangqiPendingPremoveProvider(gameId));
      cancelPremove();
      if (queued?.move.from == square) return;
      final piece = state.gamePosition.pieceAt(square);
      if (piece == null || piece.side != state.mySide) return;
      _set(state.copyWith(selected: square));
      return;
    }
    if (selected == square) {
      _set(state.copyWith(selected: null));
      return;
    }
    if (_canPremove(premoveEnabled)) {
      if (xiangqiPremovesFrom(state.position, selected).contains(XiangqiMove(selected, square))) {
        movePiece(selected, square, premoveEnabled: true);
      } else {
        final piece = state.position.pieceAt(square);
        cancelPremove();
        _set(state.copyWith(selected: piece?.side == state.mySide ? square : null));
      }
      return;
    }
    final move = XiangqiMove(selected, square);
    if (rules.isLegal(state.position, move)) {
      _set(state.copyWith(selected: null));
      unawaited(playMove(move));
      return;
    }
    final piece = state.gamePosition.pieceAt(square);
    _set(state.copyWith(selected: piece != null && piece.side == state.mySide ? square : null));
  }

  /// Resigns, if this device is one of the two players and the game is still on.
  ///
  /// `reason` is xiangqi.com's own code for a resignation, and the ack is an empty list — there is
  /// nothing to wait for, and the state changes when `game.server.end` arrives.
  Future<void> resign() async {
    final state = _latest;
    if (state.mySide == null || state.isFinished || !state.isConnected) return;
    try {
      await _socket.emit(
        kXiangqiFinishEvent,
        data: {'game_id': gameId, 'reason': kXiangqiComEndResign},
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not resign game $gameId.', error, stackTrace);
      _set(_latest.copyWith(error: kXiangqiOnlineConnectionFailed, isConnected: false));
    }
  }

  /// Opens the socket, if it is not open already, and subscribes once it is.
  Future<void> _connect(XiangqiSocketClient socket) async {
    try {
      await socket.connect();
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not open the xiangqi.com socket for game $gameId.', error, stackTrace);
      _set(_latest.copyWith(error: kXiangqiOnlineConnectionFailed));
      return;
    }
    // The handshake also fires [connectedStream], which subscribes for itself; one of the two wins
    // and the other is dropped by [_subscribing]. The case this exists for is the socket having
    // been opened by something else already, where no event will fire at all.
    if (socket.isConnected) {
      _set(_latest.copyWith(isConnected: false));
      unawaited(_subscribe());
    }
  }

  Future<void> _onConnected(void _) async {
    if (!ref.mounted) return;
    final generation = _buildGeneration;
    final session = await ref.read(xiangqiSessionStoreProvider).read();
    if (!ref.mounted || generation != _buildGeneration) return;
    _userId = session == null ? null : _userIdFromToken(session.accessToken);
    _set(_latest.copyWith(isConnected: false));
    unawaited(_subscribe());
  }

  /// Asks the server for the game, under the one name this client ever subscribes with.
  Future<void> _subscribe() {
    if (!ref.mounted || _subscribing) return Future<void>.value();
    _set(_latest.copyWith(isConnected: false, selected: null));
    _snapshotTimeout?.cancel();
    _snapshotTimeout = Timer(const Duration(seconds: 20), () {
      if (ref.mounted) {
        _set(_latest.copyWith(error: kXiangqiOnlineConnectionFailed, isConnected: false));
      }
    });
    return _subscribeTo(kXiangqiGetEvent);
  }

  /// Sends [event] and follows the ack's redirect, and any redirect *it* is answered with.
  ///
  /// The walk is a loop rather than a recursive call, and that is not a style choice: the guard at
  /// the top is what keeps one subscription in flight at a time, so a nested `_subscribeTo` would
  /// be dropped by that guard and the redirect would never go out — the client would register the
  /// name it is waiting for and then wait for it forever.
  Future<void> _subscribeTo(String event) async {
    if (_subscribing) return;
    _subscribing = true;
    final generation = _buildGeneration;
    final followed = <String>{event};
    try {
      var name = event;
      while (true) {
        final Object? ack;
        try {
          ack = await _socket.emit(name, data: {'game_id': gameId});
        } on Object catch (error, stackTrace) {
          _logger.warning('xiangqi.com did not answer $name for game $gameId.', error, stackTrace);
          _set(_latest.copyWith(error: kXiangqiOnlineConnectionFailed, isConnected: false));
          return;
        }
        if (!ref.mounted || generation != _buildGeneration) return;
        // A finished game answers `g_v2.get` with a redirect rather than a failure: the snapshot is
        // not on `game.get.success` but on the event the ack names. Follow that name — it is the
        // server's to choose, and it has been seen spelling it `game.archived.get`. A name already
        // followed ends the walk, which is what stops a server redirecting in a circle.
        final map = _asMap(ack);
        if (map == null) return;
        final redirect = map['event'];
        if (map['status'] != 'REDIRECT' || redirect is! String || redirect.isEmpty) return;
        if (!followed.add(redirect) || followed.length > 8) return;
        _snapshotEvents.add('$redirect.success');
        name = redirect;
      }
    } finally {
      if (generation == _buildGeneration) _subscribing = false;
    }
  }

  void _onEvent(XiangqiSocketEvent event) {
    final data = _unwrap(event.data);
    final map = _asMap(data);
    final id = map?['game_id'] ?? map?['id'];
    if (id != null && id.toString() != gameId) return;
    if (_snapshotEvents.contains(event.name)) {
      _snapshotTimeout?.cancel();
      if (!_applySnapshot(data)) {
        _set(_latest.copyWith(error: kXiangqiOnlineUnreadableGame));
      }
      return;
    }
    switch (event.name) {
      case 'game.move.success' || 'game.move.opponent':
        _applyMove(data);
      case 'game.server.end':
        _applyEnd(data);
      case 'game.start.success':
        _applyStart(data);
      case 'game.error':
        _applyError(data);
      case 'game.move.rejected':
        // Never seen live, and the frame carries a `type` and nothing else, so there is nothing in
        // it to read: a move this client thought was legal was refused, and the only way to find
        // out what the position really is, is to ask.
        unawaited(_subscribe());
      default:
        break;
    }
  }

  /// Reads [data] as a whole game. Returns whether it held one.
  ///
  /// Everything here is read from the payload's own fields and nothing is assumed: a snapshot whose
  /// moves cannot all be turned into moves is refused outright rather than half-applied, because
  /// half a game is worse than none — the board would show a position that never happened and the
  /// clock would run on it as if it had.
  bool _applySnapshot(Object? data) {
    _snapshotRevision++;
    cancelPremove();
    _submittedDragMove = null;
    final map = _asMap(data);
    if (map == null) return false;
    _animateUpdate = false;
    _snapshotTimeout?.cancel();
    _pendingMove = false;
    _moveConfirmation?.cancel();
    final red = _player(map['rplayer']);
    final black = _player(map['bplayer']);
    final moves = _movesOf(map['move_history']);
    final rawInitialFen = map['initial_fen'];
    if (rawInitialFen != null && rawInitialFen is! String) return false;
    final XiangqiPosition initial;
    try {
      initial = rawInitialFen == null
          ? XiangqiPosition.initial()
          : XiangqiPosition.fromFen(rawInitialFen as String);
    } on FormatException {
      return false;
    }
    final positions = moves == null ? null : _replay(initial, moves);
    if (moves == null || positions == null) return false;
    final clocks = _clocksOf(map['timers']);
    final replayCursor = _latest.viewCursor;
    // Reconnection and foreground resync refresh the live end, not the reader's place in history.
    // Keep the cursor only while the same position still exists there; a divergent or shortened
    // history must instead display the authoritative live position.
    final keepReplayCursor =
        _latest.isLoaded &&
        !_latest.isAtLivePosition &&
        replayCursor < positions.length &&
        positions[replayCursor] == _latest.position;

    // A snapshot may be silent about how a game ended — the archived one is not obliged to repeat
    // it — and a game that has ended does not come back to life because a later frame failed to
    // mention it. The end is only ever added to, never dropped.
    final parsedEnd = _endOf(map);
    _set(
      XiangqiOnlineGameState(
        positions: positions,
        moves: moves,
        cursor: keepReplayCursor ? replayCursor : -1,
        red: red,
        black: black,
        isRated: _asBool(map['is_rated']) ?? false,
        mySide: _sideOf(red, black),
        redSeconds: clocks.red,
        blackSeconds: clocks.black,
        serverClock: clocks.serverClock,
        end: parsedEnd?.end ?? _latest.end,
        resignedBy: parsedEnd?.resignedBy ?? _latest.resignedBy,
        flaggedSide: parsedEnd?.flaggedSide ?? _latest.flaggedSide,
        isConnected: _socket.isConnected,
        isLoaded: true,
      ),
    );
    _turnStartedAt = clock.now();
    return true;
  }

  /// Reads a move, from either of the two frames that carry one.
  ///
  /// `game.move.success` and `game.move.opponent` are one shape and one code path here: which of
  /// them arrived says who made the move, and nothing about the move. The position is replayed from
  /// the move either way, and `moves_count` is what keeps the two in order — see below.
  void _applyMove(Object? data) {
    final map = _asMap(data);
    final raw = map?['move'];
    if (map == null || raw is! String) return;
    final clocks = _clocksOf(map['timers']);
    final move = xiangqiMoveFromComUci(_uciOf(raw));
    if (move == null) {
      _logger.warning('A move of game $gameId could not be read: "$raw".');
      unawaited(_subscribe());
      return;
    }

    final count = _asInt(map['moves_count']);
    final played = _latest.moves.length;
    // A move already counted is a move already on the board: the same move arrives both as its own
    // frame and as an entry of the next snapshot, and playing it twice would put the game a move
    // ahead of itself. The counters are still worth folding in — the frame is the freshest clock
    // there is.
    if (count != null && count <= played) {
      _set(_withClocks(_latest, clocks));
      return;
    }
    // A gap means frames went by while the socket was down, and one move cannot be played onto a
    // position that is missing the ones before it.
    if (count != null && count > played + 1) {
      unawaited(_subscribe());
      return;
    }

    final XiangqiPosition next;
    try {
      next = rules.play(_latest.gamePosition, move);
    } on rules.XiangqiIllegalMoveException {
      _logger.warning(
        'Game $gameId played $move, which is not legal in ${_latest.position.toFen()}.',
      );
      unawaited(_subscribe());
      return;
    }

    final previousPosition = _latest.gamePosition;
    _pendingMove = false;
    _moveConfirmation?.cancel();
    final viaDragAndDrop = _submittedDragMove == move && previousPosition.turn == _latest.mySide;
    _submittedDragMove = null;
    _animateUpdate = !viaDragAndDrop;
    _set(
      _withClocks(_latest, clocks).copyWith(
        positions: _latest.positions.add(next),
        moves: _latest.moves.add(move),
        selected: null,
        error: null,
      ),
    );
    _confirmedMoves.add((
      move: move,
      before: previousPosition,
      after: next,
      viaDragAndDrop: viaDragAndDrop,
    ));
    _turnStartedAt = clock.now();
    final premove = ref.read(xiangqiPendingPremoveProvider(gameId));
    if (premove != null && _latest.isMyTurn) {
      cancelPremove();
      final validated = validateXiangqiPremove(
        premove.position,
        next,
        premove.move,
        _latest.mySide!,
      );
      if (validated != null) unawaited(playMove(validated));
    }
  }

  /// Reads `game.server.end`.
  void _applyEnd(Object? data) {
    final map = _asMap(data);
    if (map == null) return;
    final parsed = _endOf(map);
    if (parsed == null) return;
    _set(
      _withClocks(_latest, _clocksOf(map['timers'])).copyWith(
        end: parsed.end,
        resignedBy: parsed.resignedBy,
        flaggedSide: parsed.flaggedSide,
        selected: null,
      ),
    );
    // Watching a game is the one thing here the server does not reliably end: a spectator can see
    // every move go by and never be told the game is over. Asking again costs one emit and turns
    // the final position and the result into the server's own account of them rather than an
    // inference from the last frame that happened to arrive — and for a finished game the answer
    // comes back under the archived event's name, which [_subscribeTo] follows.
    unawaited(_subscribe());
  }

  /// Reads `game.start.success`: the game has begun, and the clock has started with it.
  ///
  /// The snapshot can arrive before both seats are filled, and its `timers` are what the clocks
  /// read at that moment — before the clock was running. This frame is the server saying when it
  /// started, which is the same instant [XiangqiOnlineGameState.secondsLeftFor] counts from.
  void _applyStart(Object? data) {
    final stamp = _asInt(_asMap(data)?['server_clock']);
    if (stamp == null) return;
    _set(_latest.copyWith(serverClock: stamp));
    _turnStartedAt = clock.now();
  }

  /// Reads `game.error`, which is two frames under one name.
  ///
  /// With a `message` it is an error and the message is kept. Without one the frame *is* the game
  /// state — the server telling a client that has drifted where it really is — so it is read as a
  /// snapshot, and if it is not one, the whole thing is asked for again.
  void _applyError(Object? data) {
    final map = _asMap(data);
    if (map == null) return;
    final message = map['message'];
    if (message is String && message.isNotEmpty) {
      _set(_latest.copyWith(error: message));
      return;
    }
    if (!_applySnapshot(map)) unawaited(_subscribe());
  }

  /// [state] with a frame's clock readings folded in, leaving the ones the frame did not carry.
  XiangqiOnlineGameState _withClocks(
    XiangqiOnlineGameState state,
    ({int? red, int? black, int? serverClock}) clocks,
  ) => state.copyWith(
    redSeconds: clocks.red ?? state.redSeconds,
    blackSeconds: clocks.black ?? state.blackSeconds,
    serverClock: clocks.serverClock ?? state.serverClock,
  );

  /// The players of a snapshot, or two empty seats when it does not name them.
  XiangqiOnlinePlayer _player(Object? value) {
    final map = _asMap(value);
    if (map == null) return XiangqiOnlinePlayer.empty;
    return XiangqiOnlinePlayer(
      id: _asString(map['id']) ?? '',
      name: _asString(map['username']) ?? '',
      rating: _asInt(map['rating']),
    );
  }

  /// Which side this device plays, by matching the token's subject against the two player ids.
  ///
  /// Null for someone who is in neither seat, which is exactly what watching a game is. The guest
  /// seats are named by id the same way real accounts are (`guest7zuq8`), so there is no special
  /// case for them.
  XiangqiSide? _sideOf(XiangqiOnlinePlayer red, XiangqiOnlinePlayer black) {
    final me = _userId;
    if (me == null || me.isEmpty) return null;
    if (red.id == me) return XiangqiSide.red;
    if (black.id == me) return XiangqiSide.black;
    return null;
  }

  /// The moves of a snapshot's `move_history`, or null if any entry is not a move.
  ///
  /// All or nothing: one entry that cannot be read would leave a hole, and every move after it
  /// would be replayed onto a position that never existed. The list is refused instead, and the
  /// caller asks the server again.
  ///
  /// Each entry is a whole record — `"c3d5 577/120 570/120 3"` — of which only the leading token is
  /// the move. The other three fields are the clocks and the time that move took, none of which is
  /// needed: the frame's own `timers` object carries the clocks, and the clocks are the thing the
  /// board shows.
  IList<XiangqiMove>? _movesOf(Object? value) {
    if (value is! List) return null;
    final moves = <XiangqiMove>[];
    for (final entry in value) {
      if (entry is! String) return null;
      final move = xiangqiMoveFromComUci(_uciOf(entry));
      if (move == null) return null;
      moves.add(move);
    }
    return moves.lock;
  }

  /// The whole game, replayed from the starting position, or null if a move will not play.
  ///
  /// Replayed rather than taken from the snapshot's own `fen`: the FEN would be one more thing the
  /// server could spell differently from this repo, and the moves are the game. It is the check as
  /// well as the construction — a `move_history` that does not replay is a history this client does
  /// not understand, which is worth knowing before it is put on a board.
  IList<XiangqiPosition>? _replay(XiangqiPosition initial, IList<XiangqiMove> moves) {
    final positions = <XiangqiPosition>[initial];
    var position = positions.first;
    for (final move in moves) {
      try {
        position = rules.play(position, move);
      } on rules.XiangqiIllegalMoveException {
        return null;
      }
      positions.add(position);
    }
    return positions.lock;
  }

  /// The clock readings of a `timers` object, the ones it does not carry as null.
  ({int? red, int? black, int? serverClock}) _clocksOf(Object? value) {
    final map = _asMap(value);
    if (map == null) return (red: null, black: null, serverClock: null);
    return (
      red: _asInt(_asMap(map['red'])?['game_secs']),
      black: _asInt(_asMap(map['black'])?['game_secs']),
      serverClock: _asInt(map['server_clock']),
    );
  }

  /// The side that lost, from an `end_result` object, or null when it names none.
  ///
  /// `end_result` is the only place the loser is written down: `game.server.end` has no winner
  /// field, only this pair of `{factor, result}` objects, and the two `result` values it uses are
  /// [kXiangqiComResultWin] for the side that won and [kXiangqiComResultLoss] for the side that did
  /// not. Both sides are looked at rather than one assumed, because a draw is a pair of equal
  /// results and a game nobody lost has no loser to name.
  XiangqiSide? _loserOf(Map<String, Object?> map) {
    final result = _asMap(map['end_result']);
    if (result == null) return null;
    for (final side in XiangqiSide.values) {
      if (_asInt(_asMap(result[side.name])?['result']) == kXiangqiComResultLoss) return side;
    }
    return null;
  }

  /// How the game ended, or null when the payload does not say.
  ///
  /// Null covers two different things deliberately. A payload with no `end_reason` is not an ending
  /// at all. And an ending whose loser cannot be named is one this screen would have to invent a
  /// sentence for: [XiangqiGameEnd] has one member per real outcome, and "somebody resigned" with
  /// nobody attached to it is not one of them. The state stays live and the next frame is waited
  /// for instead of a result being claimed on no evidence.
  ///
  /// Three of the codes are mapped to the nearest thing the enum has rather than to something
  /// invented, and all three are approximations:
  /// * 400, 401 and 402 are the three ways xiangqi.com draws a game, and
  ///   [XiangqiGameEnd.threefoldRepetition] is the only draw the enum has.
  /// * 500 and 600 — a lost connection and an abandoned game — end a game the way giving up does,
  ///   with a loser and no position to point at, so they are read as resignations.
  /// 700 (a challenge nobody answered) and 800 (a puzzle) are left unmapped: neither is a game this
  /// app ever shows.
  XiangqiOnlineEnd? _endOf(Map<String, Object?> map) {
    final reason = _asInt(map['end_reason']);
    if (reason == null) return null;
    final loser = _loserOf(map);
    return switch (reason) {
      kXiangqiComEndCheckmate => (
        end: XiangqiGameEnd.checkmate,
        resignedBy: null,
        flaggedSide: null,
      ),
      kXiangqiComEndStalemate => (
        end: XiangqiGameEnd.stalemate,
        resignedBy: null,
        flaggedSide: null,
      ),
      kXiangqiComEndDraw || kXiangqiComEndDrawNoCapture || kXiangqiComEndDrawNoThreatPattern => (
        end: XiangqiGameEnd.threefoldRepetition,
        resignedBy: null,
        flaggedSide: null,
      ),
      kXiangqiComEndTimerExpired || kXiangqiComEndDisconnectTimerExpired =>
        loser == null ? null : (end: XiangqiGameEnd.timeout, resignedBy: null, flaggedSide: loser),
      kXiangqiComEndResign || kXiangqiComEndDisconnect || kXiangqiComEndAbandon =>
        loser == null ? null : (end: XiangqiGameEnd.resign, resignedBy: loser, flaggedSide: null),
      _ => null,
    };
  }

  /// Puts [next] in place.
  ///
  /// Held back while the first build is still running: Riverpod refuses a write before `build` has
  /// returned, and the frames of a fast connection can land while the empty state is still being
  /// assembled. [_built] closes that window — the state is kept either way, and the build hands
  /// back the latest one it has.
  void _set(XiangqiOnlineGameState next) {
    if (!ref.mounted) return;
    if (!next.isConnected || next.isFinished || next.mySide != _latest.mySide) {
      _submittedDragMove = null;
      cancelPremove();
    }
    _latest = next;
    if (!_built || !ref.mounted) return;
    state = AsyncData(next);
  }
}

final xiangqiConfirmedMoveProvider = StreamProvider.autoDispose
    .family<XiangqiConfirmedMove, String>((ref, gameId) {
      return ref.watch(xiangqiOnlineGameControllerProvider(gameId).notifier).confirmedMoves;
    }, name: 'XiangqiConfirmedMoveProvider');

/// The UCI at the head of one of xiangqi.com's move strings.
///
/// A move in a frame is a whole record — `"c3d5 577/120 570/120 3"` — and the move in it is the
/// first whitespace-separated token, which is also how the shipped bundle splits it.
String _uciOf(String entry) {
  final space = entry.indexOf(' ');
  return space == -1 ? entry : entry.substring(0, space);
}

/// The payload of a frame, unwrapped.
///
/// Most of the `game.*` frames put what they have to say one level in, under `data`; a snapshot puts
/// it at the top. Both are handled here rather than at each call site, so that a reader of a frame
/// is written against the thing it reads and not against the envelope it arrived in.
Object? _unwrap(Object? data) {
  final map = _asMap(data);
  return map?['data'] ?? data;
}

/// [value] as a string-keyed map, or null if it is not one.
///
/// Built by hand rather than with `Map.cast`, which is lazy: a cast map throws where it is read,
/// which would be somewhere far away from the frame that was wrong.
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

/// [value] as an int, or null. JSON gives whole numbers back as `int`, but a number written with a
/// point (`300.0`) comes back as a `double` and is taken as one.
int? _asInt(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : null;

bool? _asBool(Object? value) => value is bool ? value : null;

/// The `sub` of [token] as a string, or null if it cannot be read.
///
/// The payload segment is base64url-decoded and read without checking the signature: this is our own
/// token, handed to us over TLS by the service we are talking to, so it is not a trust boundary. A
/// real account's `sub` is a number (`100001`) and a guest's is a string (`guest7zuq8`), so both are
/// accepted and normalised to a string.
///
/// The same decode `xiangqi_auth_controller.dart:246` makes, written out again rather than reached
/// for through [xiangqiAuthControllerProvider]. This controller wants one string out of the token
/// and nothing else from that session, and depending on the account controller would keep it — and
/// the guest sign-in it offers — alive for as long as any game screen is open.
String? _userIdFromToken(String token) {
  final segments = token.split('.');
  if (segments.length < 2) return null;
  final Object? payload;
  try {
    payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))));
  } catch (_) {
    return null;
  }
  if (payload is! Map<String, dynamic>) return null;
  final sub = payload['sub'];
  if (sub is String && sub.isNotEmpty) return sub;
  if (sub is num) return sub.toString();
  return null;
}
