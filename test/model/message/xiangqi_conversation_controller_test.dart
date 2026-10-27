import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/network/socket.dart' show webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';

import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_container.dart';
import '../auth/fake_auth_storage.dart' show fakeAuthUser;
import '../xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import 'xiangqi_inbox_repository_test.dart' as fixture;

class _MutableAuthController() extends AuthController {
  @override
  AuthUser? build() => fakeAuthUser;

  void signOutImmediately() {
    state = null;
  }
}

final conversation = (
  chatId: fixture.xiangqiFirstChatId,
  peerId: fixture.xiangqiFirstPeerId,
  peer: xiangqiLightUser(fixture.xiangqiFirstPeerId, fixture.xiangqiFirstPeerName),
);

Future<({ProviderContainer container, fixture.XiangqiInboxHarness inbox})>
makeControllerHarness() async {
  final factory = fx.FakeXiangqiChannelFactory();
  final container = await makeContainer(
    overrides: {
      authControllerProvider: authControllerProvider.overrideWith(_MutableAuthController.new),
      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
        FakeXiangqiAuthStorage(signedInSession.copyWith(userId: fixture.xiangqiAccountId)),
      ),
      webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(factory),
      xiangqiInboxRepositoryProvider: xiangqiInboxRepositoryProvider.overrideWith((ref) {
        ref.watch(xiangqiAccountGenerationProvider);
        final repository = XiangqiInboxRepository(
          socket: ref.watch(xiangqiSocketProvider),
          storage: ref.read(xiangqiAuthStorageProvider),
          sessionStore: ref.read(xiangqiSessionStoreProvider),
          spacing: Duration.zero,
        );
        ref.onDispose(repository.dispose);
        return repository;
      }),
    },
  );
  await container.read(xiangqiSessionStoreProvider).ready;
  final repository = container.read(xiangqiInboxRepositoryProvider);
  await pumpEventQueue();
  return (
    container: container,
    inbox: fixture.XiangqiInboxHarness(repository: repository, factory: factory),
  );
}

void main() {
  test('an identity change during a message load discards the superseded build', () async {
    final harness = await makeControllerHarness();
    final container = harness.container;
    final provider = xiangqiConversationControllerProvider(conversation);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await fixture.completeHandshake(harness.inbox);

    (container.read(authControllerProvider.notifier) as _MutableAuthController)
        .signOutImmediately();
    await pumpEventQueue();
    harness.inbox.channel.fromServer(
      fixture.xiangqiMessagesFrame([fixture.xiangqiMessageRow('Superseded history')]),
    );
    await pumpEventQueue();
    expect(container.read(provider).isLoading, isTrue);
    expect(
      harness.inbox.events.where((event) => event == kXiangqiInboxChatUserEvent),
      hasLength(2),
    );

    harness.inbox.channel.fromServer(
      fixture.xiangqiMessagesFrame([fixture.xiangqiMessageRow('Current history')]),
    );
    final current = await container.read(provider.future);
    expect(current.me.id, xiangqiUserId(fixture.xiangqiAccountId));
    expect(current.convo.messages.map((message) => message.text), ['Current history']);
  });

  test('rebuilding the conversation retains only the current incoming subscription', () async {
    final harness = await makeControllerHarness();
    final container = harness.container;
    final provider = xiangqiConversationControllerProvider(conversation);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await fixture.completeHandshake(harness.inbox);
    harness.inbox.channel.fromServer(
      fixture.xiangqiMessagesFrame([fixture.xiangqiMessageRow('Original history')]),
    );
    await container.read(provider.future);

    container.invalidate(provider);
    await pumpEventQueue();
    harness.inbox.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxMessageSentEvent, {
        'data': fixture.xiangqiMessageRow('Old build event', senderId: fixture.xiangqiFirstPeerId),
      }),
    );
    harness.inbox.channel.fromServer(
      fixture.xiangqiMessagesFrame([fixture.xiangqiMessageRow('Reloaded history')]),
    );
    await container.read(provider.future);
    harness.inbox.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxMessageSentEvent, {
        'data': fixture.xiangqiMessageRow('New incoming', senderId: fixture.xiangqiFirstPeerId),
      }),
    );
    await pumpEventQueue();
    expect(container.read(provider).requireValue.convo.messages.map((message) => message.text), [
      'New incoming',
      'Reloaded history',
    ]);
  });

  test('token rotation preserves loaded contacts while signing out clears them', () async {
    final harness = await makeControllerHarness();
    final container = harness.container;
    final listener = container.listen(xiangqiContactsProvider, (_, _) {});
    addTearDown(listener.close);
    await fixture.completeHandshake(harness.inbox);
    harness.inbox.channel.fromServer(fixture.xiangqiChatsFrame([fixture.xiangqiFirstChatRow]));
    final original = container.read(xiangqiContactsProvider.future);
    expect(await original, hasLength(1));

    final store = container.read(xiangqiSessionStoreProvider);
    await store.write(
      store.current!.copyWith(accessToken: 'rotated-access', refreshToken: 'rotated-refresh'),
    );
    await pumpEventQueue();
    expect(container.read(xiangqiContactsProvider.future), same(original));

    await store.write(null);
    await pumpEventQueue();
    expect(await container.read(xiangqiContactsProvider.future), isEmpty);
  });
}
