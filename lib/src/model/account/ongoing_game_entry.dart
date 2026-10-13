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
}
