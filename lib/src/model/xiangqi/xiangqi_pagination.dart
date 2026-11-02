import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiPagination');

class const XiangqiPagedState<T>({
  required final IList<T> items,
  required final IList<int> loadedPages,
  required final int currentPage,
  required final int? nextPage,
  required final int? previousPage,
  required final int? totalPages,
  final bool refreshing = false,
  final bool loadingMore = false,
  final Object? refreshError,
  final Object? moreError,
}) {
  bool get busy => refreshing || loadingMore;
}

/// Fresh reads, independent operation feedback and atomic refresh of the visible page range.
///
/// Subclasses watch their repository in build and provide a direct read, not a cached provider's
/// already completed future. Account/query rebuilds invalidate every older operation. Token
/// revisions do not rebuild this controller.
abstract class XiangqiPagedController<T> extends AsyncNotifier<XiangqiPagedState<T>> {
  final Map<int, XiangqiPage<T>> _pages = {};
  int _generation = 0;
  Future<void>? _more;
  Future<void>? _refresh;

  bool get appendPages => true;
  Future<XiangqiPage<T>> loadPage(int page);
  Object itemKey(T item);

  @override
  Future<XiangqiPagedState<T>> build() async {
    ref.watch(xiangqiAccountGenerationProvider);
    final generation = ++_generation;
    _pages.clear();
    _more = null;
    _refresh = null;
    ref.onDispose(() {
      _generation++;
      _pages.clear();
    });
    final page = await loadPage(1);
    if (!_current(generation)) throw StateError('Page load cancelled.');
    _pages[page.currentPage] = page;
    return _snapshot();
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  XiangqiPagedState<T> _snapshot({
    bool refreshing = false,
    bool loadingMore = false,
    Object? refreshError,
    Object? moreError,
  }) {
    final pages = _pages.values.toList();
    final last = pages.isEmpty ? null : pages.last;
    final unique = <Object, T>{};
    for (final page in pages) {
      for (final item in page.items) {
        unique.putIfAbsent(itemKey(item), () => item);
      }
    }
    return XiangqiPagedState(
      items: unique.values.toIList(),
      loadedPages: pages.map((page) => page.currentPage).toIList(),
      currentPage: last?.currentPage ?? 1,
      nextPage: last?.nextPage,
      previousPage: last?.previousPage,
      totalPages: last?.totalPages ?? (pages.isEmpty ? null : pages.first.totalPages),
      refreshing: refreshing,
      loadingMore: loadingMore,
      refreshError: refreshError,
      moreError: moreError,
    );
  }

  Future<void> getMore() {
    if (_more case final active?) return active;
    if (_pages.isEmpty || !state.hasValue || state.requireValue.refreshing) {
      return Future<void>.value();
    }
    final next = state.requireValue.nextPage;
    return next == null ? Future<void>.value() : goToPage(next);
  }

  Future<void> goToPage(int page) {
    if (_more case final active?) return active;
    if (_pages.isEmpty || !state.hasValue || state.requireValue.refreshing) {
      return Future<void>.value();
    }
    if (page < 1) return Future.error(RangeError.range(page, 1, null, 'page'));
    final generation = _generation;
    final future = _loadMore(generation, page);
    _more = future;
    unawaited(
      future.then<void>((_) {
        if (_current(generation) && identical(_more, future)) _more = null;
      }),
    );
    return future;
  }

  Future<XiangqiPage<T>> _readAvailablePage(int number) async {
    final page = await loadPage(number);
    // A ranking can shrink while its last page is open. Read the declared last page rather than
    // pretending that the empty response to page N was a response to a different request.
    if (!appendPages &&
        page.items.isEmpty &&
        page.totalPages != null &&
        page.totalPages! > 0 &&
        page.currentPage > page.totalPages!) {
      return loadPage(page.totalPages!);
    }
    return page;
  }

  Future<void> _loadMore(int generation, int number) async {
    final previousError = state.requireValue.refreshError;
    state = AsyncData(_snapshot(loadingMore: true, refreshError: previousError));
    try {
      final page = await _readAvailablePage(number);
      if (!_current(generation)) return;
      if (!appendPages) _pages.clear();
      _pages[page.currentPage] = page;
      state = AsyncData(_snapshot(refreshError: previousError));
    } on Object catch (error, stackTrace) {
      if (!_current(generation)) return;
      _logger.warning('Could not load xiangqi.com page $number.', error, stackTrace);
      state = AsyncData(_snapshot(refreshError: previousError, moreError: error));
    }
  }

  Future<void> refresh() {
    if (_refresh case final active?) return active;
    if (state.isLoading) return Future<void>.value();
    final generation = ++_generation;
    _more = null;
    final hasPages = _pages.isNotEmpty;
    final count = hasPages && appendPages ? _pages.length : 1;
    final start = hasPages && !appendPages ? _pages.values.last.currentPage : 1;
    state = hasPages ? AsyncData(_snapshot(refreshing: true)) : const AsyncLoading();
    final future = _reload(generation, start, count, hasPages);
    _refresh = future;
    unawaited(
      future.then<void>((_) {
        if (_current(generation) && identical(_refresh, future)) _refresh = null;
      }),
    );
    return future;
  }

  Future<void> _reload(int generation, int start, int count, bool hasPages) async {
    final fresh = <int, XiangqiPage<T>>{};
    var number = start;
    try {
      for (var index = 0; index < count; index++) {
        final page = await _readAvailablePage(number);
        if (!_current(generation)) return;
        fresh[page.currentPage] = page;
        if (!appendPages || page.nextPage == null) break;
        number = page.nextPage!;
      }
      _pages
        ..clear()
        ..addAll(fresh);
      state = AsyncData(_snapshot());
    } on Object catch (error, stackTrace) {
      if (!_current(generation)) return;
      _logger.warning('Could not refresh xiangqi.com pages.', error, stackTrace);
      state = hasPages ? AsyncData(_snapshot(refreshError: error)) : AsyncError(error, stackTrace);
    }
  }

  /// Confirmed mutations can update every loaded page without losing its cursor or viewport.
  void updateItems(T Function(T item) transform) {
    if (!ref.mounted || _pages.isEmpty || !state.hasValue) return;
    final previous = state.requireValue;
    for (final number in _pages.keys.toList()) {
      final page = _pages[number]!;
      _pages[number] = page.withItems(page.items.map(transform).toIList());
    }
    state = AsyncData(
      _snapshot(
        refreshing: previous.refreshing,
        loadingMore: previous.loadingMore,
        refreshError: previous.refreshError,
        moreError: previous.moreError,
      ),
    );
  }
}
