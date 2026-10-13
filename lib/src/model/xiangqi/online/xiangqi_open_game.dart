import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

part 'xiangqi_open_game.freezed.dart';

/// A game the signed-in user is currently playing on xiangqi.com.
///
/// This is the xiangqi counterpart of [OngoingGame], not a translation of it:
/// xiangqi.com hands out its own side names (red and black, via [XiangqiSide]),
/// its own clock and its own move count, and it has no variant, no perf and no
/// speed. Only the two fields the merged list actually needs — [isMyTurn] and
/// the two clocks — line up with the chess model, and they line up by meaning,
/// not by shape, so they are carried here rather than derived from a shared
/// scalar.
@freezed
sealed class const XiangqiOpenGame._() with _$XiangqiOpenGame {
  const factory({
    required String id,
    required bool isRated,

    /// The side this user plays, derived by matching the `rplayer`/`bplayer` id
    /// against the JWT `sub`.
    required XiangqiSide mySide,
    required int gameTimeSeconds,
    required int incrementSeconds,
    required LightUser opponent,
    int? opponentRating,
    required bool isMyTurn,
    required int movesCount,
    required String fen,
    int? redSecondsLeft,
    int? blackSecondsLeft,
  }) = _XiangqiOpenGame;
}
