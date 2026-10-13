import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_material.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

/// The position the game starts from, and the number every row is checked against.
const _initialFen = kXiangqiInitialFen;

/// The initial position with black's top-left chariot taken off the board.
///
/// One piece, and a chariot, because that is the piece whose value is furthest from a round number:
/// if the tally were rounding anything off, this is the row that would move.
const _redAChariotUpFen = '1nbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

/// A position with nothing on it but the two generals, for the empty-tally case.
const _bareFen = '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1';

void main() {
  group('xiangqiPieceValue', () {
    test("counts the pieces in Pikafish's own units", () {
      // The `Value` constants the search reads its piece values out of: RookValue, AdvisorValue,
      // CannonValue, PawnValue, KnightValue, BishopValue. Spelled out here rather than compared to
      // the constants, because the point of the table is the numbers themselves — a tally that
      // says a horse is worth what a cannon is worth is a different game from this one.
      expect(xiangqiPieceValue(.rook), 1305);
      expect(xiangqiPieceValue(.cannon), 773);
      expect(xiangqiPieceValue(.knight), 720);
      expect(xiangqiPieceValue(.advisor), 219);
      expect(xiangqiPieceValue(.bishop), 187);
      expect(xiangqiPieceValue(.pawn), kXiangqiPawnValue);
      expect(kXiangqiPawnValue, 144);
    });

    test('a general is worth nothing at all', () {
      // Losing one ends the game rather than costing material: Pikafish's own `KING` entry is
      // `VALUE_ZERO`, and a tally that priced it would be ranking a piece that is never traded.
      expect(xiangqiPieceValue(.king), 0);
    });

    test('the order of the pieces is the order a player puts them in', () {
      // The engine's own judgement, not this file's: a chariot outranks a cannon, a cannon a horse,
      // and the two guards are the cheapest things on the board apart from the general.
      expect(xiangqiPieceValue(.rook), greaterThan(xiangqiPieceValue(.cannon)));
      expect(xiangqiPieceValue(.cannon), greaterThan(xiangqiPieceValue(.knight)));
      expect(xiangqiPieceValue(.knight), greaterThan(xiangqiPieceValue(.advisor)));
      expect(xiangqiPieceValue(.advisor), greaterThan(xiangqiPieceValue(.bishop)));
      expect(xiangqiPieceValue(.bishop), greaterThan(xiangqiPieceValue(.pawn)));
    });

    test('every kind has a value, and only the general has none', () {
      final values = {for (final type in XiangqiPieceType.values) type: xiangqiPieceValue(type)};

      expect(values, hasLength(XiangqiPieceType.values.length));
      expect(values.values.where((value) => value == 0), hasLength(1));
      expect(values.values.toSet(), hasLength(XiangqiPieceType.values.length));
    });
  });

  group('xiangqiPieceValueInPawns', () {
    test('one soldier is one point, and the pieces come out as they do to a player', () {
      expect(xiangqiPieceValueInPawns(.pawn), 1.0);
      expect(xiangqiPieceValueInPawns(.knight), 5.0);
      expect(xiangqiPieceValueInPawns(.rook), closeTo(9.06, 0.01));
      expect(xiangqiPieceValueInPawns(.cannon), closeTo(5.37, 0.01));
      expect(xiangqiPieceValueInPawns(.advisor), closeTo(1.52, 0.01));
      expect(xiangqiPieceValueInPawns(.bishop), closeTo(1.30, 0.01));
      expect(xiangqiPieceValueInPawns(.king), 0.0);
    });

    test('it is the raw value over one soldier, and nothing else', () {
      for (final type in XiangqiPieceType.values) {
        expect(
          xiangqiPieceValueInPawns(type),
          xiangqiPieceValue(type) / kXiangqiPawnValue,
          reason: 'the two spellings of a piece must not be able to disagree',
        );
      }
    });
  });

  group('xiangqiMaterialCount', () {
    test('counts a side on the position every game starts from', () {
      final position = XiangqiPosition.fromFen(_initialFen);

      // Two chariots, two cannons, two horses, two guards, two elephants and five soldiers — the
      // five soldiers are more than half of it, which is the thing about xiangqi material that a
      // chess-shaped intuition gets wrong.
      expect(
        xiangqiMaterialCount(position, .red),
        2 * 1305 + 2 * 773 + 2 * 720 + 2 * 219 + 2 * 187 + 5 * 144,
      );
      expect(xiangqiMaterialCount(position, .red), 7128);
      expect(xiangqiMaterialCount(position, .black), 7128);
    });

    test('the two sides are counted separately', () {
      final position = XiangqiPosition.fromFen(_redAChariotUpFen);

      expect(xiangqiMaterialCount(position, .red), 7128);
      expect(
        xiangqiMaterialCount(position, .black),
        7128 - 1305,
        reason: "it is black's chariot that is missing",
      );
    });

    test('a board with only the generals on it counts nothing', () {
      final position = XiangqiPosition.fromFen(_bareFen);

      expect(xiangqiMaterialCount(position, .red), 0);
      expect(xiangqiMaterialCount(position, .black), 0);
    });
  });

  group('xiangqiMaterialDifference', () {
    test('the starting position is level', () {
      final position = XiangqiPosition.fromFen(_initialFen);

      expect(xiangqiMaterialDifference(position), 0);
      expect(xiangqiMaterialDifferenceInPawns(position), 0.0);
    });

    test('a missing black chariot is a chariot to red', () {
      final position = XiangqiPosition.fromFen(_redAChariotUpFen);

      expect(xiangqiMaterialDifference(position), 1305);
      expect(xiangqiMaterialDifferenceInPawns(position), closeTo(9.06, 0.01));
    });

    test('the sign is red minus black, on both sides of level', () {
      const redDown = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/1NBAKABNR w - - 0 1';

      expect(xiangqiMaterialDifference(XiangqiPosition.fromFen(_redAChariotUpFen)), greaterThan(0));
      expect(xiangqiMaterialDifference(XiangqiPosition.fromFen(redDown)), lessThan(0));

      // And the two are exact mirrors, because the two tallies are of the same board.
      expect(
        xiangqiMaterialDifference(XiangqiPosition.fromFen(_redAChariotUpFen)),
        -xiangqiMaterialDifference(XiangqiPosition.fromFen(redDown)),
      );
    });

    test('it is the difference of the two counts, and nothing else', () {
      final position = XiangqiPosition.fromFen(_redAChariotUpFen);

      expect(
        xiangqiMaterialDifference(position),
        xiangqiMaterialCount(position, .red) - xiangqiMaterialCount(position, .black),
      );
      expect(
        xiangqiMaterialDifferenceInPawns(position),
        xiangqiMaterialDifference(position) / kXiangqiPawnValue,
      );
    });

    test('nothing about the position but its pieces changes the tally', () {
      // The same board with the other side to move, and with the counters wound on: material is a
      // fact about the pieces, so the clocks must not be able to move the number.
      final blackToMove = XiangqiPosition.fromFen(
        _redAChariotUpFen.replaceFirst(' w ', ' b ').replaceFirst('- 0 1', '- 47 23'),
      );

      expect(xiangqiMaterialDifference(blackToMove), 1305);
      expect(xiangqiMaterialDifferenceInPawns(blackToMove), closeTo(9.06, 0.01));
    });
  });
}
