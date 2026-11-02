import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';

void main() {
  XiangqiPage<int> page(Map<String, Object?> metadata, {int number = 1}) =>
      XiangqiPage.fromMetadata(
        items: const IListConst<int>([]),
        requestedPage: number,
        metadata: metadata,
      );

  test('retains the request page and explicit pagination metadata', () {
    final result = page({
      'total_pages': 3,
      'has_next_page': true,
      'next_page_num': 3,
      'prev_page_num': 1,
    }, number: 2);
    expect(result.currentPage, 2);
    expect(result.nextPage, 3);
    expect(result.previousPage, 1);
    expect(result.totalPages, 3);
  });

  test('missing totals and cursors remain unknown instead of being invented', () {
    final result = page({});
    expect(result.totalPages, isNull);
    expect(result.nextPage, isNull);
    expect(result.previousPage, isNull);
  });

  test('accepts a genuine empty result and terminal page', () {
    expect(page({'total_pages': 0, 'has_next_page': false}).items, isEmpty);
    expect(page({'total_pages': 2, 'has_next_page': false}, number: 2).nextPage, isNull);
  });

  for (final metadata in <Map<String, Object?>>[
    {'next_page_num': 1},
    {'next_page_num': 2.5},
    {'next_page_num': 0},
    {'next_page_num': 2, 'has_next_page': false},
    {'has_next_page': true},
    {'total_pages': -1},
    {'total_pages': 1, 'next_page_num': 2},
    {'prev_page_num': 1},
    {'current_page': 2},
  ]) {
    test('rejects contradictory or invalid pagination metadata $metadata', () {
      expect(() => page(metadata), throwsFormatException);
    });
  }

  test('rejects a non-empty result claiming zero pages', () {
    expect(
      () => XiangqiPage.fromMetadata(
        items: const IListConst<int>([1]),
        requestedPage: 1,
        metadata: const {'total_pages': 0},
      ),
      throwsFormatException,
    );
  });

  test('rejects page zero before making any request', () {
    expect(() => page({}, number: 0), throwsArgumentError);
  });
}
