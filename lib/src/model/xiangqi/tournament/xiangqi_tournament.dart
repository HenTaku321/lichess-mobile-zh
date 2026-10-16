import 'dart:io' show HttpDate;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_live_game.dart';

part 'xiangqi_tournament.freezed.dart';

/// One tournament, from `GET /api/tournament/list` or `GET /api/tournament/<id>`.
@freezed
sealed class const XiangqiTournament._() with _$XiangqiTournament {
  const factory({
    /// The id everything else is asked for by: a short opaque string, not the numeric
    /// `tournament_id` a participant carries.
    required String id,
    required String name,

    /// xiangqi.com's own state code. `10` and `30` were measured — one running or waiting to start,
    /// and one over — and the rest of the enum is not pinned, so nothing here branches on it.
    required int state,

    /// When it starts, or null when the server did not say.
    ///
    /// **An RFC-1123 date**, not the ISO the rest of the site uses — measured on 2026-10-16 as
    /// `"Sun, 18 Oct 2026 13:00:00 GMT"`.
    DateTime? startsAt,

    required int rounds,
    required int currentRound,

    /// The time control: `gameTimerSeconds` and `moveTimerSeconds` are minutes on the wire and
    /// `incrementSeconds` is seconds, the same pair of units every other xiangqi.com game uses.
    required int gameTimerSeconds,
    required int moveTimerSeconds,
    required int incrementSeconds,

    required bool isRated,

    /// How many accounts have signed up.
    required int participants,

    /// How many of them have taken a seat. **A different number from [participants]**, and the two
    /// are what tell a tournament that is filling up from one that has started.
    required int joinedParticipants,

    /// How many games are being played right now.
    required int ongoingGames,

    /// Whether this account may sign up — only on the detail endpoint.
    bool? canRegister,

    /// Whether this account may take a seat — only on the detail endpoint.
    bool? userCanJoin,

    /// Whether this account has already taken one — only on the detail endpoint.
    bool? userHasJoined,
  }) = _XiangqiTournament;

  /// Whether the tournament is over, as far as this app can tell.
  ///
  /// `30` is the one code measured for a finished tournament. A code this app has never seen is
  /// read as not over, because saying a tournament is finished when it is not is the worse mistake.
  bool get isFinished => state == kXiangqiTournamentFinishedState;
}

/// The one state code measured for a tournament that is over.
const int kXiangqiTournamentFinishedState = 30;

/// The list of tournaments, from `GET /api/tournament/list`.
///
/// **Two arrays and not a page.** The endpoint splits them itself — the ones that are on and the
/// ones that are over — and takes no page parameter.
@freezed
sealed class const XiangqiTournaments._() with _$XiangqiTournaments {
  const factory({
    required IList<XiangqiTournament> active,
    required IList<XiangqiTournament> previous,
  }) = _XiangqiTournaments;
}

/// One account's standing in a tournament, from `GET /api/tournament/<id>/participants/invited`.
@freezed
sealed class const XiangqiTournamentParticipant._() with _$XiangqiTournamentParticipant {
  const factory({
    required XiangqiLivePlayer player,

    /// Where they sit, or 0 before anything has been played.
    required int rank,
    required int totalScore,

    /// The performance rating the server computed, or null.
    double? performance,
    required int winCount,
    required int gameCount,

    /// How many of their games they played red, which is a statistic the site keeps for reasons of
    /// its own.
    required int redCount,
  }) = _XiangqiTournamentParticipant;
}

/// The tournaments a `tournament/list` body holds.
XiangqiTournaments xiangqiTournamentsFromJson(Object? json) {
  final map = _map(json);
  return XiangqiTournaments(
    active: _tournamentsOf(map?['active']),
    previous: _tournamentsOf(map?['previous']),
  );
}

/// The tournament a `tournament/<id>` body describes, or null when it is not one.
XiangqiTournament? xiangqiTournamentFromJson(Object? json) {
  final map = _map(json);
  if (map == null) return null;
  final id = _string(map['id']);
  final name = _string(map['name']);
  if (id == null || name == null) return null;
  return _tournamentOf(map, id: id, name: name);
}

/// The standings of a `tournament/<id>/leaders` body.
///
/// The list key is **`participants`** and not the `items` every other page on the site uses —
/// measured on 2026-10-16. See `xiangqi-com-re/docs/tournament.md`.
XiangqiMasterPageLike<XiangqiTournamentParticipant> xiangqiTournamentLeadersFromJson(Object? json) {
  final map = _map(json);
  return (
    items: _participantsOf(map?['participants']),
    totalPages: _int(map?['total_pages']) ?? 0,
    nextPage: _int(map?['next_page_num']),
  );
}

/// The participants of a `participants/invited` or `participants/joined` body.
///
/// **A bare array**, not a page — measured that way on both.
IList<XiangqiTournamentParticipant> xiangqiTournamentParticipantsFromJson(Object? json) =>
    _participantsOf(json);

/// A `{items, total_pages, next_page_num}` shape, as a record.
///
/// A record rather than a class because it is a page and nothing else: the two lists that use it
/// have their own item types and share nothing but the envelope, and a generic class for one shape
/// would be a class with one field's worth of meaning.
typedef XiangqiMasterPageLike<T> = ({IList<T> items, int totalPages, int? nextPage});

IList<XiangqiTournament> _tournamentsOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiTournament>([]);
  final tournaments = <XiangqiTournament>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final id = _string(map['id']);
    final name = _string(map['name']);
    if (id == null || name == null) continue;
    tournaments.add(_tournamentOf(map, id: id, name: name));
  }
  return tournaments.lock;
}

XiangqiTournament _tournamentOf(
  Map<String, dynamic> map, {
  required String id,
  required String name,
}) => XiangqiTournament(
  id: id,
  name: name,
  state: _int(map['state']) ?? 0,
  startsAt: _httpDate(map['starts_at']),
  rounds: _int(map['rounds']) ?? 0,
  currentRound: _int(map['current_round']) ?? 0,
  gameTimerSeconds: (_int(map['game_timer']) ?? 0) * 60,
  moveTimerSeconds: (_int(map['move_timer']) ?? 0) * 60,
  incrementSeconds: _int(map['increment']) ?? 0,
  isRated: map['is_rated'] == true,
  participants: _int(map['participants']) ?? 0,
  joinedParticipants: _int(map['joined_participants']) ?? 0,
  ongoingGames: _int(map['ongoing_games']) ?? 0,
  canRegister: map['can_register'] == null ? null : map['can_register'] == true,
  userCanJoin: map['user_can_join'] == null ? null : map['user_can_join'] == true,
  userHasJoined: map['user_has_joined'] == null ? null : map['user_has_joined'] == true,
);

IList<XiangqiTournamentParticipant> _participantsOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiTournamentParticipant>([]);
  final participants = <XiangqiTournamentParticipant>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final player = xiangqiLivePlayerFromJson(map['user']);
    if (player == null) continue;
    participants.add(
      XiangqiTournamentParticipant(
        player: player,
        rank: _int(map['rank']) ?? 0,
        totalScore: _int(map['total_score']) ?? 0,
        performance: _double(map['performance']),
        winCount: _int(map['win_count']) ?? 0,
        gameCount: _int(map['game_count']) ?? 0,
        redCount: _int(map['red_count']) ?? 0,
      ),
    );
  }
  return participants.lock;
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

/// The instant an RFC-1123 HTTP-date names, or null if it cannot be read.
///
/// The tournament list spells its dates this way where the rest of the site spells them ISO — see
/// `xiangqi-com-re/docs/tournament.md` — so `DateTime.parse` is not enough for it.
DateTime? _httpDate(Object? value) {
  if (value is! String) return null;
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return null;
  }
}
