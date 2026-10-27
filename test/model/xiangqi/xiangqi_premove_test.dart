import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_premove.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;

void main() {
  XiangqiSquare square(String value) => XiangqiSquare.parse(value)!;
  XiangqiMove move(String value) => XiangqiMove.parseIccs(value)!;

  test('premove geometry ignores current blockers but never authorises a move', () {
    final position = XiangqiPosition.initial();
    expect(xiangqiPremovesFrom(position, square('a0')), contains(move('a0a9')));
    expect(rules.isLegal(position, move('a0a9')), isFalse);
    expect(xiangqiPremovesFrom(position, square('b0')), contains(move('b0d1')));
  });

  test('soldiers keep their direction and only move sideways across the river', () {
    final position = XiangqiPosition.initial();
    expect(xiangqiPremovesFrom(position, square('a3')), [move('a3a4')]);
    expect(xiangqiPremovesFrom(position, square('a6')), [move('a6a5')]);
    final crossed = rules.playForced(position, move('a3a5'));
    expect(
      xiangqiPremovesFrom(crossed, square('a5')),
      unorderedEquals([move('a5b5'), move('a5a6')]),
    );
  });

  test('generals, advisors and elephants retain their palace/river boundaries', () {
    final position = XiangqiPosition.initial();
    expect(xiangqiPremovesFrom(position, square('e0')), contains(move('e0e1')));
    expect(xiangqiPremovesFrom(position, square('e0')), isNot(contains(move('e0e3'))));
    expect(xiangqiPremovesFrom(position, square('d0')), [move('d0e1')]);
    final advanced = rules.playForced(position, move('c0e4'));
    expect(xiangqiPremovesFrom(advanced, square('e4')), isNot(contains(move('e4g6'))));
  });

  test('a premove for a captured piece is discarded', () {
    final before = XiangqiPosition.initial();
    final after = rules.playForced(before, move('a9a3'));
    expect(validateXiangqiPremove(before, after, move('a3a4'), .red), isNull);
  });

  test('a premove is legal only on the new position and correct turn', () {
    final before = rules.play(XiangqiPosition.initial(), move('e3e4'));
    final after = rules.play(before, move('e6e5'));
    expect(validateXiangqiPremove(before, after, move('a3a4'), .red), move('a3a4'));
    expect(validateXiangqiPremove(before, before, move('a3a4'), .red), isNull);
    expect(validateXiangqiPremove(before, after, move('a0a9'), .red), isNull);
  });
}
