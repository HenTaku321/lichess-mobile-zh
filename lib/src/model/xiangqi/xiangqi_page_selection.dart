import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:logging/logging.dart';

final _logger = Logger('XiangqiPageSelection');

class const XiangqiSelectedPage<T>({
  required final T page,
  required final int pageNumber,
  final int? requestedPage,
  final bool busy = false,
  final Object? error,
});

/// Page-number navigation is transactional: the accepted page remains visible until its target
/// succeeds. A failed navigation retries that target, not the visible page or an implicit cursor.
abstract class XiangqiPageSelectionController<T>() extends AsyncNotifier<XiangqiSelectedPage<T>> {
  int _generation = 0;
  Future<void>? _request;
  int? _failedPage;

  Future<T> loadPage(int number);
  int? totalPages(T page);
  bool isEmpty(T page);
  int? responsePage(T page) => null;

  bool _current(int generation) => ref.mounted && generation == _generation;

  @override
  Future<XiangqiSelectedPage<T>> build() async {
    final generation = ++_generation;
    _request = null;
    _failedPage = null;
    ref.onDispose(() => _generation++);
    await ref.watch(xiangqiSessionReadyProvider.future);
    if (!_current(generation)) throw StateError('Page selection cancelled.');
    ref.watch(xiangqiAccountGenerationProvider);
    final result = await _read(1, generation);
    if (!_current(generation)) throw StateError('Page selection cancelled.');
    return XiangqiSelectedPage(page: result.page, pageNumber: result.number);
  }

  Future<({T page, int number})> _read(int number, int generation) async {
    final page = await loadPage(number);
    if (!_current(generation)) throw StateError('Page selection cancelled.');
    final actual = responsePage(page);
    if (actual != null && actual != number) {
      throw const FormatException('The selected page response has a different page identity.');
    }
    final count = totalPages(page);
    if (count != null && count < 0) throw const FormatException('Negative selected page count.');
    if (count != null && number > (count == 0 ? 1 : count) && isEmpty(page)) {
      // The collection may shrink while a last page is open. Read its declared last page before
      // selecting it; never relabel an old/empty response as a response to an unissued request.
      final last = count == 0 ? 1 : count;
      final replacement = await loadPage(last);
      if (!_current(generation)) throw StateError('Page selection cancelled.');
      if (responsePage(replacement) != null && responsePage(replacement) != last) {
        throw const FormatException('The fallback selected page has a different identity.');
      }
      return (page: replacement, number: last);
    }
    return (page: page, number: number);
  }

  Future<void> selectPage(int number) {
    if (_request case final active?) return active;
    if (number < 1) return Future.error(RangeError.range(number, 1, null, 'number'));
    if (state.isLoading) return Future<void>.value();
    return _start(number);
  }

  Future<void> refresh() => selectPage(state.value?.pageNumber ?? 1);
  Future<void> retry() => selectPage(_failedPage ?? state.value?.pageNumber ?? 1);

  Future<void> _start(int number) {
    final generation = ++_generation;
    final previous = state.value;
    _failedPage = null;
    state = previous == null
        ? const AsyncLoading()
        : AsyncData(
            XiangqiSelectedPage(
              page: previous.page,
              pageNumber: previous.pageNumber,
              requestedPage: number,
              busy: true,
            ),
          );
    final future = _navigate(number, generation, previous);
    _request = future;
    unawaited(
      future.then<void>((_) {
        if (_current(generation) && identical(_request, future)) _request = null;
      }),
    );
    return future;
  }

  Future<void> _navigate(int number, int generation, XiangqiSelectedPage<T>? previous) async {
    try {
      final result = await _read(number, generation);
      if (!_current(generation)) return;
      state = AsyncData(XiangqiSelectedPage(page: result.page, pageNumber: result.number));
    } on Object catch (error, stackTrace) {
      if (!_current(generation)) return;
      _failedPage = number;
      _logger.warning('Could not select xiangqi.com page $number.', error, stackTrace);
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(
              XiangqiSelectedPage(
                page: previous.page,
                pageNumber: previous.pageNumber,
                error: error,
              ),
            );
    }
  }
}
