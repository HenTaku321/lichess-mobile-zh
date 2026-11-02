import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_page.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_pagination.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';

import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_container.dart';

class _Pager(final Future<XiangqiPage<String>> Function(int) reader)
    extends XiangqiPagedController<String> {
  @override
  Future<XiangqiPage<String>> loadPage(int page) => reader(page);

  @override
  Object itemKey(String item) => item;
}

XiangqiPage<String> page(int number, String text) => XiangqiPage(
  items: [text].lock,
  currentPage: number,
  nextPage: number == 1 ? 2 : null,
  previousPage: number == 1 ? null : 1,
  totalPages: 2,
);

void main() {
  test('more is deduplicated and a failed more keeps the loaded content and cursor', () async {
    final calls = <int>[];
    final more = Completer<XiangqiPage<String>>();
    var failed = false;
    final provider = AsyncNotifierProvider.autoDispose<_Pager, XiangqiPagedState<String>>(
      () => _Pager((number) async {
        calls.add(number);
        if (number == 1) return page(1, 'old first');
        return failed ? page(2, 'second') : await more.future;
      }),
    );
    final container = await makeContainer();
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    final first = controller.getMore();
    expect(controller.getMore(), same(first));
    await pumpEventQueue();
    more.completeError(StateError('Unavailable second page'));
    await first;
    expect(container.read(provider).requireValue.items, ['old first']);
    expect(container.read(provider).requireValue.nextPage, 2);
    expect(container.read(provider).requireValue.moreError, isA<StateError>());
    failed = true;
    await controller.getMore();
    expect(calls, [1, 2, 2]);
    expect(container.read(provider).requireValue.items, ['old first', 'second']);
    expect(container.read(provider).requireValue.nextPage, isNull);
  });

  test(
    'refresh stages the full loaded range and retry resumes its failed suffix atomically',
    () async {
      final calls = <int>[];
      var refreshing = false;
      var retrying = false;
      final held = Completer<XiangqiPage<String>>();
      final provider = AsyncNotifierProvider.autoDispose<_Pager, XiangqiPagedState<String>>(
        () => _Pager((number) async {
          calls.add(number);
          if (!refreshing) return page(number, 'old $number');
          if (number == 2 && !retrying) return await held.future;
          return page(number, 'fresh $number');
        }),
      );
      final container = await makeContainer();
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      await controller.getMore();
      refreshing = true;
      final refresh = controller.refresh();
      await pumpEventQueue();
      expect(container.read(provider).requireValue.items, ['old 1', 'old 2']);
      expect(container.read(provider).requireValue.refreshing, isTrue);
      held.completeError(StateError('Unavailable suffix'));
      await refresh;
      expect(container.read(provider).requireValue.items, ['old 1', 'old 2']);
      expect(container.read(provider).requireValue.refreshError, isA<StateError>());
      retrying = true;
      await controller.retryRefresh();
      expect(calls, [1, 2, 1, 2, 2]);
      expect(container.read(provider).requireValue.items, ['fresh 1', 'fresh 2']);
      expect(container.read(provider).requireValue.refreshError, isNull);
    },
  );

  test('a superseded more cannot overwrite a completed refresh', () async {
    final held = Completer<XiangqiPage<String>>();
    var refreshing = false;
    final provider = AsyncNotifierProvider.autoDispose<_Pager, XiangqiPagedState<String>>(
      () => _Pager((number) async {
        if (number == 2) return await held.future;
        return page(1, refreshing ? 'fresh' : 'old');
      }),
    );
    final container = await makeContainer();
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    final more = controller.getMore();
    await pumpEventQueue();
    refreshing = true;
    await controller.refresh();
    held.complete(page(2, 'late old second'));
    await more;
    expect(container.read(provider).requireValue.items, ['fresh']);
    expect(container.read(provider).requireValue.loadedPages, [1]);
  });

  test('token renewal retains the page range but a new account starts with page one', () async {
    final calls = <int>[];
    final provider = AsyncNotifierProvider.autoDispose<_Pager, XiangqiPagedState<String>>(
      () => _Pager((number) async {
        calls.add(number);
        return page(number, 'page $number');
      }),
    );
    final container = await makeContainer(
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(signedInSession),
        ),
      },
    );
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    await container.read(provider.notifier).getMore();
    final sessions = container.read(xiangqiSessionStoreProvider);
    await sessions.write(sessions.current!.copyWith(accessToken: 'rotated token'));
    await pumpEventQueue();
    expect(calls, [1, 2]);
    expect(container.read(provider).requireValue.loadedPages, [1, 2]);
    await sessions.write(sessions.current!.copyWith(userId: 'another-account', name: 'Another'));
    await pumpEventQueue();
    await container.read(provider.future);
    expect(calls, [1, 2, 1]);
    expect(container.read(provider).requireValue.loadedPages, [1]);
  });
}
