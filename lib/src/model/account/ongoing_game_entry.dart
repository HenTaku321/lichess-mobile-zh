import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/backend/source.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_open_game.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// One row of the merged ongoing-games list.
///
/// The list brings two independent backends ([BackendSource]) onto one screen,
/// but it merges the *lists* and never the rows: a lichess game and a xiangqi
/// game are different objects whose ratings live on different scales, so fusing
/// a username, a rating or an avatar across them would be fabricating data.
/// Each subclass therefore keeps its own backend's game type whole, and the
/// getters here are the only things the merged list reads — enough to sort and
/// to show a "your turn" badge without either side pretending to be the other.
sealed class OngoingGameEntry() {
  /// A stable key for this row, unique across both backends.
  ///
  /// Backend-prefixed, so two backends that happen to hand out the same id can
  /// never collide in a list keyed by it.
  String get rowKey;

  /// The backend this row came from.
  BackendSource get source;

  /// Whether it is this user's turn in this game.
  bool get isMyTurn;

  /// Seconds left on this user's clock, or `null` for a game without a running
  /// clock (correspondence).
  int? get secondsLeft;

  /// Whether this is a live game rather than a correspondence one.
  ///
  /// This belongs on the sealed type and not on either backend's own game
  /// object because the home carousel sorts real-time games ahead of
  /// correspondence ones, and it sorts a *merged* list. By the time the order is
  /// decided the two backends' rows are one list of these, and a chess game's own
  /// `isRealTime` — which is the only place the concept is spelled out — is no
  /// longer reachable from the row being sorted.
  bool get isRealTime;
}

/// An ongoing game on lichess.
final class ChessOngoingGame(final OngoingGame game) extends OngoingGameEntry {
  @override
  BackendSource get source => BackendSource.lichess;

  @override
  String get rowKey => 'lichess:${game.fullId.value}';

  @override
  bool get isMyTurn => game.isMyTurn;

  @override
  int? get secondsLeft => game.secondsLeft;

  @override
  bool get isRealTime => game.isRealTime;
}

/// An ongoing game on xiangqi.com.
final class XiangqiOngoingGame(final XiangqiOpenGame game) extends OngoingGameEntry {
  @override
  BackendSource get source => BackendSource.xiangqiCom;

  @override
  String get rowKey => 'xiangqi:${game.id}';

  @override
  bool get isMyTurn => game.isMyTurn;

  @override
  int? get secondsLeft =>
      game.mySide == XiangqiSide.red ? game.redSecondsLeft : game.blackSecondsLeft;

  /// Every game xiangqi.com hands this list is a live one.
  ///
  /// This is not read off the game, because [XiangqiOpenGame] has no speed to read:
  /// xiangqi.com does have a daily/correspondence form, so the backend is not
  /// missing the concept — it is behind an activated account, and the guest path
  /// this app plays through cannot reach it, so a correspondence xiangqi row is
  /// not a shape that can arrive here today.
  @override
  bool get isRealTime => true;
}
