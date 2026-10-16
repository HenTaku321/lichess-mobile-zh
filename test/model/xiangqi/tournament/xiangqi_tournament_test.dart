// Tests for reading xiangqi.com's tournaments.
//
// The shapes are the ones the 2026-10-16 probe measured — see `xiangqi-com-re/docs/tournament.md` —
// with every value replaced. Not one id, name or date here is the capture's.
//
// Three cases are about the shapes this domain does *not* share with the rest of the site: the list
// is two arrays rather than a page, the standings key is `participants` rather than `items`, and the
// dates are RFC-1123 where every other date on the site is ISO.

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/tournament/xiangqi_tournament.dart';

/// One tournament, with the fields both endpoints carry.
Map<String, Object?> tournament({
  String id = 'AbCdEf',
  String name = 'A Cup (5+2)',
  int state = 10,
  int rounds = 7,
  int currentRound = 0,
  int participants = 11,
  int joinedParticipants = 0,
  bool isRated = false,
}) => {
  'id': id,
  'name': name,
  'state': state,
  'starts_at': 'Sun, 18 Oct 2026 13:00:00 GMT',
  'rounds': rounds,
  'current_round': currentRound,
  'game_timer': 5,
  'move_timer': 2,
  'increment': 2,
  'is_rated': isRated,
  'participants': participants,
  'joined_participants': joinedParticipants,
  'ongoing_games': 0,
};

/// One participant.
Map<String, Object?> participant({
  String name = 'A Player',
  int rank = 0,
  int totalScore = 0,
  int winCount = 0,
  int gameCount = 0,
}) => {
  'tournament_id': 405,
  'rank': rank,
  'total_score': totalScore,
  'performance': 0.0,
  'win_count': winCount,
  'game_count': gameCount,
  'red_count': 0,
  'status': 0,
  'game_results': <Object?>[],
  'user': {
    'id': 238943,
    'username': name,
    'identity': name,
    'rating': null,
    'country': {'code': 'ID', 'name': 'Indonesia'},
    'hidden_username': false,
    'hidden_profile_icon': false,
    'profile_image': null,
    'profile_link_token': null,
  },
};

void main() {
  group('the list', () {
    test('is two arrays and not a page', () {
      // The endpoint splits them itself — the ones that are on and the ones that are over — and
      // takes no page parameter.
      final list = xiangqiTournamentsFromJson({
        'active': [tournament(id: 'on')],
        'previous': [tournament(id: 'over', state: 30)],
      });
      expect(list.active.map((t) => t.id), ['on']);
      expect(list.previous.map((t) => t.id), ['over']);
      expect(list.active.single.isFinished, isFalse);
      expect(list.previous.single.isFinished, isTrue);
    });

    test('is empty for a body that is not one', () {
      expect(xiangqiTournamentsFromJson(null).active, isEmpty);
      expect(xiangqiTournamentsFromJson(null).previous, isEmpty);
      expect(xiangqiTournamentsFromJson(const {'active': 'nope'}).active, isEmpty);
    });

    test('drops a row with no id or no name', () {
      final list = xiangqiTournamentsFromJson({
        'active': [
          tournament(id: 'a'),
          {...tournament(id: 'b')}..remove('name'),
          tournament(id: 'c'),
        ],
      });
      expect(list.active.map((t) => t.id), ['a', 'c']);
    });
  });

  group('one tournament', () {
    test('is read field for field, with the two units the site uses', () {
      final read = xiangqiTournamentFromJson(tournament())!;
      expect(read.id, 'AbCdEf');
      expect(read.name, 'A Cup (5+2)');
      expect(read.state, 10);
      expect(read.rounds, 7);
      expect(read.currentRound, 0);
      // `game_timer` and `move_timer` are minutes on the wire and `increment` is seconds.
      expect(read.gameTimerSeconds, 300);
      expect(read.moveTimerSeconds, 120);
      expect(read.incrementSeconds, 2);
      expect(read.isRated, isFalse);
      expect(read.participants, 11);
      expect(read.joinedParticipants, 0);
      expect(read.ongoingGames, 0);
    });

    test('reads its date as an RFC-1123 one', () {
      // Every other date on the site is ISO; this one is not, so `DateTime.parse` would drop it.
      final read = xiangqiTournamentFromJson(tournament())!;
      expect(read.startsAt, isNotNull);
      expect(read.startsAt!.toUtc(), DateTime.utc(2026, 10, 18, 13));
    });

    test('carries the three fields only the detail endpoint has', () {
      final read = xiangqiTournamentFromJson({
        ...tournament(),
        'can_register': true,
        'user_can_join': false,
        'user_has_joined': false,
      })!;
      expect(read.canRegister, isTrue);
      expect(read.userCanJoin, isFalse);
      expect(read.userHasJoined, isFalse);
    });

    test('leaves those three null when the list is what answered', () {
      // The list does not carry them, and null is what says "this payload did not say" rather than
      // "the answer was no".
      final read = xiangqiTournamentFromJson(tournament())!;
      expect(read.canRegister, isNull);
      expect(read.userCanJoin, isNull);
      expect(read.userHasJoined, isNull);
    });

    test('is null for a body that is not one', () {
      expect(xiangqiTournamentFromJson(null), isNull);
      expect(xiangqiTournamentFromJson(const {'id': 'a'}), isNull);
    });
  });

  group('the standings', () {
    test('are read from the participants key and not from items', () {
      // Measured on 2026-10-16: this is the one page on the site whose list is not called `items`.
      final leaders = xiangqiTournamentLeadersFromJson({
        'participants': [participant(rank: 1, totalScore: 12, winCount: 4, gameCount: 6)],
        'total_pages': 2,
        'next_page_num': 2,
      });
      expect(leaders.items.length, 1);
      expect(leaders.items.single.rank, 1);
      expect(leaders.items.single.totalScore, 12);
      expect(leaders.items.single.winCount, 4);
      expect(leaders.items.single.gameCount, 6);
      expect(leaders.items.single.player.name, 'A Player');
      expect(leaders.totalPages, 2);
      expect(leaders.nextPage, 2);
    });

    test('are empty when the key is missing, which is what a wrong reader would read', () {
      expect(xiangqiTournamentLeadersFromJson(const {'items': <Object?>[]}).items, isEmpty);
    });
  });

  group('the participants', () {
    test('are a bare array and not a page', () {
      final participants = xiangqiTournamentParticipantsFromJson([participant()]);
      expect(participants.length, 1);
      expect(participants.single.player.name, 'A Player');
      expect(participants.single.player.countryName, 'Indonesia');
    });

    test('are empty for a body that is not one', () {
      expect(xiangqiTournamentParticipantsFromJson(null), isEmpty);
      expect(xiangqiTournamentParticipantsFromJson(const {'items': <Object?>[]}), isEmpty);
    });

    test('drop a row with nobody in it', () {
      final participants = xiangqiTournamentParticipantsFromJson([
        participant(name: 'a'),
        {...participant(name: 'b')}..remove('user'),
        participant(name: 'c'),
      ]);
      expect(participants.map((p) => p.player.name), ['a', 'c']);
    });
  });
}
