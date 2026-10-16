import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

part 'xiangqi_master_game.freezed.dart';

/// One player in the master-games database, from `GET /api/master-games/players`.
@freezed
sealed class const XiangqiMasterPlayer._() with _$XiangqiMasterPlayer {
  const factory({
    /// The **numeric** id, which is what the player's own endpoints are asked for by. A game is
    /// asked for by slug instead; the two spellings are the server's own and neither works for the
    /// other.
    required int id,
    required String name,

    /// The title the database files them under, or null when it files none.
    ///
    /// `Xiangqi Grandmaster` and `Xiangqi Master` were both measured; the set is not pinned, so
    /// nothing here branches on it.
    String? title,

    /// How many games of theirs the database holds.
    required int gameCount,
  }) = _XiangqiMasterPlayer;
}

/// One player's record, from `GET /api/master-games/players/<id>/stats`.
@freezed
sealed class const XiangqiMasterStats._() with _$XiangqiMasterStats {
  const factory({
    required String name,
    String? title,

    /// The country as a two-letter code, or null.
    ///
    /// **A bare code and not an object**, unlike every other country on the site — measured on
    /// 2026-10-16, where the same field is `{"code": "CN", "name": "China"}` everywhere else.
    String? country,
    required int wins,
    required int losses,
    required int draws,
    required int totalGames,
  }) = _XiangqiMasterStats;
}

/// One game in a player's list, from `GET /api/master-games/players/<id>/games`.
///
/// A row and not a game: the moves are not in the list — see [XiangqiMasterGame], which is what the
/// slug is for.
@freezed
sealed class const XiangqiMasterGameRow._() with _$XiangqiMasterGameRow {
  const factory({
    /// The game's slug, which is what its own endpoint is asked for by.
    required String slug,

    required String redPlayer,
    required String blackPlayer,
    String? redCountry,
    String? blackCountry,
    String? tournamentName,
    String? tournamentDate,
    required int moveCount,

    /// How the game went **for the player the list was asked for**: `won`, `lost` or `drawn`.
    ///
    /// Relative, not absolute: the same game read from the other player's page says the opposite.
    String? resultForPlayer,
  }) = _XiangqiMasterGameRow;
}

/// A page of a master-games list.
@freezed
sealed class const XiangqiMasterPage<T>._() with _$XiangqiMasterPage<T> {
  const factory({required IList<T> items, required int totalPages, int? nextPage}) =
      _XiangqiMasterPage<T>;

  /// Whether there is a page after this one.
  bool get hasNextPage => nextPage != null;
}

/// A whole game out of the database, from `GET /api/master-games/games/<slug>`.
///
/// ## Why this one is easy
///
/// It is the cleanest game this project has found on xiangqi.com: its `initial_fen` is a **standard
/// xiangqi FEN** — the `w` side letter and the `rnbakabnr` piece letters, the same spelling the
/// puzzle domain uses — and its `moves` are **standard ICCS** (`h2e2`, ranks counted from zero),
/// which is the very spelling [XiangqiMove.parseIccs] reads. Nothing has to be translated, which is
/// not true of a lesson's position or of a game's list entry. See
/// `xiangqi-com-re/docs/database.md`.
@freezed
sealed class const XiangqiMasterGame._() with _$XiangqiMasterGame {
  const factory({
    required String slug,
    required String redPlayer,
    required String blackPlayer,
    String? redTitle,
    String? blackTitle,
    String? redCountry,
    String? blackCountry,
    String? tournamentName,
    String? tournamentDate,

    /// `red_win`, `black_win` or `draw`.
    String? result,

    /// The opening the database files the game under, or null. `"-"` — the one value measured — is
    /// read as no opening at all.
    String? opening,

    required XiangqiPosition initialPosition,

    /// Every move of the game, in this repo's ICCS.
    required IList<XiangqiMove> moves,

    /// Every position of the game: one longer than [moves], the first being [initialPosition].
    ///
    /// Empty when a move does not fit the position before it, which is a game this app will not
    /// draw half of — a board showing a position that never happened is worse than no board.
    required IList<XiangqiPosition> positions,
  }) = _XiangqiMasterGame;

  /// Which side won, or null for a draw or a game the server did not call.
  XiangqiSide? get winner => switch (result) {
    'red_win' => XiangqiSide.red,
    'black_win' => XiangqiSide.black,
    _ => null,
  };

  /// Whether the game can be drawn at all.
  bool get isPlayable => positions.length == moves.length + 1;
}

/// The players of a `master-games/players` body.
XiangqiMasterPage<XiangqiMasterPlayer> xiangqiMasterPlayersFromJson(Object? json) {
  final map = _map(json);
  final items = <XiangqiMasterPlayer>[];
  final rows = map?['items'];
  if (rows is List) {
    for (final row in rows) {
      final entry = _map(row);
      if (entry == null) continue;
      final id = _int(entry['id']);
      final name = _string(entry['name']);
      if (id == null || name == null) continue;
      items.add(
        XiangqiMasterPlayer(
          id: id,
          name: name,
          title: _string(entry['title']),
          gameCount: _int(entry['game_count']) ?? 0,
        ),
      );
    }
  }
  return XiangqiMasterPage(
    items: items.lock,
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The record a `master-games/players/<id>/stats` body describes.
XiangqiMasterStats xiangqiMasterStatsFromJson(Object? json) {
  final map = _map(json);
  return XiangqiMasterStats(
    name: _string(map?['name']) ?? '',
    title: _string(map?['title']),
    country: _string(map?['country']),
    wins: _int(map?['wins']) ?? 0,
    losses: _int(map?['losses']) ?? 0,
    draws: _int(map?['draws']) ?? 0,
    totalGames: _int(map?['total_games']) ?? 0,
  );
}

/// The games of a `master-games/players/<id>/games` body.
XiangqiMasterPage<XiangqiMasterGameRow> xiangqiMasterGamesFromJson(Object? json) {
  final map = _map(json);
  final items = <XiangqiMasterGameRow>[];
  final rows = map?['items'];
  if (rows is List) {
    for (final row in rows) {
      final entry = _map(row);
      if (entry == null) continue;
      final slug = _string(entry['slug']);
      final red = _string(entry['red_player']);
      final black = _string(entry['black_player']);
      if (slug == null || red == null || black == null) continue;
      items.add(
        XiangqiMasterGameRow(
          slug: slug,
          redPlayer: red,
          blackPlayer: black,
          redCountry: _string(entry['red_country']),
          blackCountry: _string(entry['black_country']),
          tournamentName: _string(entry['tournament_name']),
          tournamentDate: _string(entry['tournament_date']),
          moveCount: _int(entry['move_count']) ?? 0,
          resultForPlayer: _string(entry['result_for_player']),
        ),
      );
    }
  }
  return XiangqiMasterPage(
    items: items.lock,
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The game a `master-games/games/<slug>` body describes, or null when it is not one.
XiangqiMasterGame? xiangqiMasterGameFromJson(Object? json) {
  final map = _map(json);
  if (map == null) return null;
  final slug = _string(map['slug']);
  final red = _map(map['red_player']);
  final black = _map(map['black_player']);
  final fen = _string(map['initial_fen']);
  if (slug == null || red == null || black == null || fen == null) return null;

  final XiangqiPosition initial;
  try {
    initial = XiangqiPosition.fromFen(fen);
  } catch (_) {
    return null;
  }

  final moves = <XiangqiMove>[];
  final rows = map['moves'];
  if (rows is List) {
    for (final row in rows) {
      if (row is! String) continue;
      final move = XiangqiMove.parseIccs(row);
      if (move == null) continue;
      moves.add(move);
    }
  }

  // Every position, or none: a game whose moves do not all fit the position before them is not a
  // game this app will draw half of.
  final positions = <XiangqiPosition>[initial];
  var position = initial;
  for (final move in moves) {
    if (!rules.isLegal(position, move)) {
      positions.clear();
      break;
    }
    position = rules.play(position, move);
    positions.add(position);
  }

  final opening = _string(map['opening']);
  return XiangqiMasterGame(
    slug: slug,
    redPlayer: _string(red['name']) ?? '',
    blackPlayer: _string(black['name']) ?? '',
    redTitle: _string(red['title']),
    blackTitle: _string(black['title']),
    redCountry: _string(map['red_country']),
    blackCountry: _string(map['black_country']),
    tournamentName: _string(map['tournament_name']),
    tournamentDate: _string(map['tournament_date']),
    result: _string(map['result']),
    // The one value measured for this field is `"-"`, which is the database saying it has no name
    // for the opening rather than an opening called `-`.
    opening: opening == '-' ? null : opening,
    initialPosition: initial,
    moves: moves.lock,
    positions: positions.lock,
  );
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;
