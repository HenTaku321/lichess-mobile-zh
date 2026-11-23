import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat_drafts.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';

import '../../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../../test_container.dart';

void main() {
  const english = (kind: XiangqiChatKind.lobby, room: 'English');
  const game = (kind: XiangqiChatKind.game, room: 'English');

  test(
    'drafts remain in memory without retaining the room controller and separate chat kinds',
    () async {
      final container = await makeContainer(
        overrides: {
          xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
            FakeXiangqiAuthStorage(signedInSession),
          ),
        },
      );
      await container.read(xiangqiSessionStoreProvider).read();
      final subscription = container.listen(xiangqiChatDraftsProvider, (_, _) {});
      final drafts = container.read(xiangqiChatDraftsProvider.notifier);
      drafts.remember(english, 'English draft');
      drafts.remember(game, 'Game draft');
      subscription.close();
      await pumpEventQueue(times: 2);
      expect(container.read(xiangqiChatDraftsProvider)[english], 'English draft');
      expect(container.read(xiangqiChatDraftsProvider)[game], 'Game draft');
      drafts.remember(english, '');
      expect(container.read(xiangqiChatDraftsProvider).containsKey(english), isFalse);
      expect(container.read(xiangqiChatDraftsProvider)[game], 'Game draft');
    },
  );

  for (final change in ['none', 'edit', 'token renewal', 'sign out and back in']) {
    test('a delayed send only clears its own unchanged draft ($change)', () async {
      final container = await makeContainer(
        overrides: {
          xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
            FakeXiangqiAuthStorage(signedInSession),
          ),
        },
      );
      final sessions = container.read(xiangqiSessionStoreProvider);
      await sessions.read();
      final subscription = container.listen(xiangqiChatDraftsProvider, (_, _) {});
      addTearDown(subscription.close);
      final drafts = container.read(xiangqiChatDraftsProvider.notifier);
      final account = sessions.accountGeneration;
      drafts.remember(english, 'Queued message');
      switch (change) {
        case 'none':
          break;
        case 'edit':
          drafts.remember(english, 'New draft');
        case 'token renewal':
          await sessions.write(signedInSession.copyWith(accessToken: 'renewed-token'));
        case 'sign out and back in':
          await sessions.write(null);
          await sessions.write(signedInSession);
          await pumpEventQueue();
          drafts.remember(english, 'Queued message');
      }
      drafts.clearSent(english, 'Queued message', accountGeneration: account);
      expect(container.read(xiangqiChatDraftsProvider)[english], switch (change) {
        'edit' => 'New draft',
        'sign out and back in' => 'Queued message',
        _ => null,
      });
    });
  }

  test('token renewal keeps drafts but signing out and back in clears them', () async {
    final container = await makeContainer(
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(signedInSession),
        ),
      },
    );
    final sessions = container.read(xiangqiSessionStoreProvider);
    await sessions.read();
    final subscription = container.listen(xiangqiChatDraftsProvider, (_, _) {});
    addTearDown(subscription.close);
    final drafts = container.read(xiangqiChatDraftsProvider.notifier);
    drafts.remember(english, 'Private account draft');
    await sessions.write(signedInSession.copyWith(accessToken: 'renewed-access-token'));
    await pumpEventQueue(times: 2);
    expect(container.read(xiangqiChatDraftsProvider)[english], 'Private account draft');
    await sessions.write(null);
    await pumpEventQueue(times: 2);
    expect(container.read(xiangqiChatDraftsProvider), isEmpty);
    await sessions.write(signedInSession);
    await pumpEventQueue(times: 2);
    expect(container.read(xiangqiChatDraftsProvider), isEmpty);
  });
}
