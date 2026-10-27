import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson_controller.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../../network/fake_http_client_factory.dart';
import '../../../test_container.dart';
import 'xiangqi_lesson_controller_test.dart' as fixture;

void main() {
  test('failed saves retain the solved board and retry only once concurrently', () async {
    var calls = 0;
    final retry = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/complete')) {
        calls++;
        return calls == 1 ? http.Response('', 503) : await retry.future;
      }
      return http.Response('{}', 200);
    });
    final container = await makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
      },
    );
    final chapter = fixture.chariotChapter();
    final provider = xiangqiChapterControllerProvider(chapter);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(provider.notifier);
    controller.movePiece(fixture.move('i0i9').from, fixture.move('i0i9').to);
    expect(container.read(provider).isSolved, isTrue);
    final solvedPosition = container.read(provider).position;
    await pumpEventQueue(times: 30);
    expect(
      container.read(xiangqiLessonSaveStateProvider(chapter.id)),
      XiangqiLessonSaveState.failed,
    );
    final pending = controller.retryComplete();
    final duplicate = controller.retryComplete();
    await duplicate;
    expect(
      container.read(xiangqiLessonSaveStateProvider(chapter.id)),
      XiangqiLessonSaveState.saving,
    );
    retry.complete(http.Response('{}', 200));
    await pending;
    expect(calls, 2);
    expect(
      container.read(xiangqiLessonSaveStateProvider(chapter.id)),
      XiangqiLessonSaveState.saved,
    );
    expect(container.read(provider).position, solvedPosition);
  });

  test('undo ignores a delayed completion from the superseded attempt', () async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    final container = await makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
      },
    );
    final chapter = fixture.chariotChapter();
    final provider = xiangqiChapterControllerProvider(chapter);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(provider.notifier);
    final move = fixture.move('i0i9');
    controller.movePiece(move.from, move.to);
    controller.undo();
    response.complete(http.Response('{}', 200));
    await pumpEventQueue(times: 30);
    expect(container.read(provider).isSolved, isFalse);
    expect(container.read(xiangqiLessonSaveStateProvider(chapter.id)), XiangqiLessonSaveState.idle);
  });
}
