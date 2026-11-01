import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_options.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_tree.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_export.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position_validation.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_replay.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

XiangqiMove move(String iccs) => XiangqiMove.parseIccs(iccs)!;
const diagram = '3k5/9/9/9/9/8p/9/9/9/4K3R w - - 0 1';

IList<XiangqiPosition> teachingPositions(XiangqiPosition start, IList<XiangqiMove> moves) {
  final positions = <XiangqiPosition>[start];
  for (final move in moves) {
    positions.add(rules.playForced(positions.last, move));
  }
  return positions.lock;
}

XiangqiPosition withCounters(
  XiangqiPosition position, {
  int halfmoveClock = 0,
  int fullmoveNumber = 1,
}) => XiangqiPosition(
  board: position.board,
  turn: position.turn,
  halfmoveClock: halfmoveClock,
  fullmoveNumber: fullmoveNumber,
);

void main() {
  test(
    'standard training history keeps exact recorded positions and editable game capabilities',
    () {
      final moves = IList([move('h2e2'), move('h9g7')]);
      final positions = teachingPositions(XiangqiPosition.initial(), moves);
      final snapshot = XiangqiReplaySnapshot.training(
        sourceId: 'standard',
        positions: positions,
        moves: moves,
        initialCursor: 1,
        orientation: .black,
      );
      final options = XiangqiAnalysisOptions.snapshot(snapshot);
      expect(snapshot.kind, XiangqiReplayKind.game);
      expect(
        options.root.lineThrough(moves).positions.map((p) => p.toFen()),
        snapshot.recordedFens,
      );
      expect(options.initialCursor, 1);
      expect(options.orientation, XiangqiSide.black);
      expect(options.capabilities.engine, isTrue);
      expect(options.capabilities.editHistory, isTrue);
    },
  );

  test('consecutive teaching moves retain every step and cannot gain game editing permissions', () {
    final moves = IList([move('i0i1'), move('i1i2')]);
    final positions = teachingPositions(XiangqiPosition.fromFen(diagram), moves);
    final snapshot = XiangqiReplaySnapshot.training(
      sourceId: 'teaching',
      positions: positions,
      moves: moves,
    );
    final options = XiangqiAnalysisOptions.snapshot(snapshot);
    final tree = XiangqiAnalysisNode.fromReplay(snapshot);
    expect(snapshot.kind, XiangqiReplayKind.teaching);
    expect(tree.lineThrough(moves).positions.map((p) => p.toFen()), snapshot.recordedFens);
    expect(tree.lineThrough(moves).moves, moves);
    expect(options.capabilities.editHistory, isFalse);
    expect(options.capabilities.engine, isFalse);
    expect(options.capabilities.editPosition, isFalse);
    expect(options.capabilities.exportHistory, isTrue);
    expect(options.capabilities.continueGame, isTrue);
    expect(xiangqiTeachingExport(positions, moves), contains('2. 车一进一 [i1i2]'));
  });

  test('recorded snapshots reject counter corruption even when position equality ignores it', () {
    final before = XiangqiPosition.initial();
    final played = move('h2e2');
    final after = rules.play(before, played);
    final corrupt = withCounters(after, fullmoveNumber: 7);
    expect(corrupt, after);
    for (final kind in XiangqiReplayKind.values) {
      expect(
        () => XiangqiReplaySnapshot.recorded(
          sourceId: 'corrupt',
          kind: kind,
          positions: IList([before, corrupt]),
          moves: IList([played]),
        ),
        throwsFormatException,
      );
    }
  });

  test('replay factories never silently truncate or accept empty-source teaching moves', () {
    final start = XiangqiPosition.initial();
    final emptySource = move('a1a2');
    expect(
      () => XiangqiReplaySnapshot.recorded(
        sourceId: 'empty-source',
        kind: .teaching,
        positions: teachingPositions(start, IList([emptySource])),
        moves: IList([emptySource]),
      ),
      throwsFormatException,
    );
    expect(
      () => XiangqiReplaySnapshot.recorded(
        sourceId: 'missing-position',
        kind: .game,
        positions: IList([start]),
        moves: IList([move('h2e2')]),
      ),
      throwsFormatException,
    );
  });

  test(
    'source cache keys include counters, replay kind and independently restricted capabilities',
    () {
      final initial = XiangqiPosition.initial();
      XiangqiAnalysisOptions options(XiangqiPosition position) => XiangqiAnalysisOptions.line(
        sourceId: 'same',
        initialPosition: position,
        moves: const IListConst([]),
      );
      final full = options(initial);
      expect(full.sourceKey, isNot(options(withCounters(initial, fullmoveNumber: 2)).sourceKey));
      final teaching = XiangqiReplaySnapshot.recorded(
        sourceId: 'same',
        kind: .teaching,
        positions: IList([initial]),
        moves: const IListConst([]),
      );
      expect(full.sourceKey, isNot(XiangqiAnalysisOptions.snapshot(teaching).sourceKey));
      final restricted = XiangqiAnalysisOptions.snapshot(
        full.replay,
        capabilities: const XiangqiAnalysisCapabilities(exportHistory: false, continueGame: false),
      );
      expect(restricted.sourceKey, isNot(full.sourceKey));
      expect(restricted.capabilities.engine, isTrue);
      expect(restricted.capabilities.exportHistory, isFalse);
      expect(restricted.capabilities.continueGame, isFalse);
    },
  );

  test('teaching diagrams without generals remain readable but do not become ordinary games', () {
    final position = XiangqiPosition.fromFen('9/9/9/9/9/9/9/9/9/8R w - - 0 1');
    final snapshot = XiangqiReplaySnapshot.training(
      sourceId: 'diagram',
      positions: teachingPositions(position, IList([move('i0i9')])),
      moves: IList([move('i0i9')]),
    );
    expect(snapshot.kind, XiangqiReplayKind.teaching);
    expect(snapshot.moves, hasLength(1));
    expect(xiangqiPositionError(snapshot.positions.last), XiangqiPositionError.generals);
  });

  group('current-position safety', () {
    test(
      'allows the initial board, valid teaching endpoint and the side-to-move being checked',
      () {
        expect(xiangqiPositionError(XiangqiPosition.initial()), isNull);
        expect(xiangqiPositionError(XiangqiPosition.fromFen(diagram)), isNull);
        expect(
          xiangqiPositionError(XiangqiPosition.fromFen('3k5/9/9/9/9/9/9/9/4r4/4K4 w - - 0 1')),
          isNull,
        );
      },
    );
    test('rejects missing and extra generals before asking the engine', () {
      expect(
        xiangqiPositionError(XiangqiPosition.fromFen('9/9/9/9/9/9/9/9/9/8R w - - 0 1')),
        XiangqiPositionError.generals,
      );
      expect(
        xiangqiPositionError(XiangqiPosition.fromFen('3kk4/9/9/9/9/9/9/9/9/4K4 w - - 0 1')),
        XiangqiPositionError.generals,
      );
    });
    test('rejects material, palace and fixed reachable-square violations', () {
      expect(
        xiangqiPositionError(XiangqiPosition.fromFen('3k5/9/9/9/9/9/9/9/CCC6/4K4 w - - 0 1')),
        XiangqiPositionError.material,
      );
      for (final fen in [
        '2k6/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
        '3k5/9/9/9/9/9/9/9/3A5/4K4 w - - 0 1',
        '3k5/9/9/9/9/9/9/9/2B6/4K4 w - - 0 1',
        '3k5/9/9/9/9/9/9/1P7/9/4K4 w - - 0 1',
      ]) {
        expect(
          xiangqiPositionError(XiangqiPosition.fromFen(fen)),
          XiangqiPositionError.placement,
          reason: fen,
        );
      }
    });
    test('rejects facing generals and an already checked inactive side', () {
      expect(
        xiangqiPositionError(XiangqiPosition.fromFen('4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1')),
        XiangqiPositionError.facingGenerals,
      );
      expect(
        xiangqiPositionError(XiangqiPosition.fromFen('3k5/9/9/9/9/9/9/9/3R5/4K4 w - - 0 1')),
        XiangqiPositionError.inactiveSideInCheck,
      );
    });
    test('rejects invalid counters but leaves a valid terminal diagram valid', () {
      expect(
        xiangqiPositionError(withCounters(XiangqiPosition.initial(), halfmoveClock: -1)),
        XiangqiPositionError.counters,
      );
      expect(
        xiangqiPositionError(withCounters(XiangqiPosition.initial(), fullmoveNumber: 0)),
        XiangqiPositionError.counters,
      );
      final mate = XiangqiPosition.fromFen('3rk4/9/9/9/9/9/9/6n2/4r4/4K4 w - - 0 1');
      expect(xiangqiPositionError(mate), isNull);
      expect(rules.isGameOver(mate), isTrue);
    });
  });
}
