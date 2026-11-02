import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A normalised page, not a guessed common wire envelope.
///
/// Each protocol locates and parses its own items first. Missing metadata remains unknown, and an
/// explicit next-page cursor is the only authority for asking for more.
class XiangqiPage<T> {
  XiangqiPage({
    required this.items,
    required this.currentPage,
    this.nextPage,
    this.previousPage,
    this.totalPages,
  }) {
    if (currentPage < 1) throw RangeError.range(currentPage, 1, null, 'currentPage');
    if (totalPages != null && totalPages! < 0) {
      throw const FormatException('Negative xiangqi.com page count.');
    }
    if (nextPage != null &&
        (nextPage! <= currentPage || (totalPages != null && nextPage! > totalPages!))) {
      throw const FormatException('Invalid xiangqi.com next-page cursor.');
    }
    if (previousPage != null && (previousPage! < 1 || previousPage! >= currentPage)) {
      throw const FormatException('Invalid xiangqi.com previous-page cursor.');
    }
    if (items.isNotEmpty &&
        (totalPages == 0 || (totalPages != null && currentPage > totalPages!))) {
      throw const FormatException('Items outside the declared xiangqi.com page range.');
    }
  }

  factory XiangqiPage.fromMetadata({
    required IList<T> items,
    required int requestedPage,
    required Map<String, Object?> metadata,
  }) {
    int? integer(String key) {
      final value = metadata[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value != value.toInt()) {
        throw FormatException('Invalid xiangqi.com $key.');
      }
      return value.toInt();
    }

    final nextPage = integer('next_page_num');
    final hasNext = metadata['has_next_page'];
    if (hasNext != null && (hasNext is! bool || hasNext != (nextPage != null))) {
      throw const FormatException('Contradictory xiangqi.com next-page metadata.');
    }
    final serverPage = integer('current_page');
    if (serverPage != null && serverPage != requestedPage) {
      throw const FormatException('The xiangqi.com response belongs to a different page.');
    }
    return XiangqiPage(
      items: items,
      currentPage: requestedPage,
      nextPage: nextPage,
      previousPage: integer('prev_page_num'),
      totalPages: integer('total_pages'),
    );
  }

  final IList<T> items;
  final int currentPage;
  final int? nextPage;
  final int? previousPage;
  final int? totalPages;

  XiangqiPage<T> withItems(IList<T> items) => XiangqiPage(
    items: items,
    currentPage: currentPage,
    nextPage: nextPage,
    previousPage: previousPage,
    totalPages: totalPages,
  );
}
