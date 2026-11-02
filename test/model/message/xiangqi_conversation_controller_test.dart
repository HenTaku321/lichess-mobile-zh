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
    inbox: fixture.XiangqiInboxHarness(
      repository: repository,
      factory: factory,
      sharedSocket: container.read(xiangqiSocketProvider),
    ),
  );
}

void main() {
  test('an unrelated sender cannot consume a pending own message with the same text', () async {
    final harness = await makeControllerHarness();
    final container = harness.container;
    final provider = xiangqiConversationControllerProvider(conversation);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await fixture.completeHandshake(harness.inbox);
    harness.inbox.channel.fromServer(fixture.xiangqiMessagesFrame([]));
    await container.read(provider.future);
    expect(await container.read(provider.notifier).sendMessage('Same text'), isTrue);
    final optimistic = container.read(provider).requireValue.convo.messages.single;

    harness.inbox.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxMessageSentEvent, {
        'data': fixture.xiangqiMessageRow('Same text', senderId: 200009),
      }),
    );
    await pumpEventQueue();
    expect(container.read(provider).requireValue.convo.messages.single, optimistic);
    expect(
      container.read(provider).requireValue.convo.messages.single.userId,
      xiangqiUserId(fixture.xiangqiAccountId),
    );
  });

  test('an ambiguous same-text own echo resyncs both chats without guessing either row', () async {
    final harness = await makeControllerHarness();
    final container = harness.container;
    final first = xiangqiConversationControllerProvider(conversation);
    final firstListener = container.listen(first, (_, _) {});
    addTearDown(firstListener.close);
    await fixture.completeHandshake(harness.inbox);
    harness.inbox.channel.fromServer(fixture.xiangqiMessagesFrame([]));
    await container.read(first.future);

    final secondKey = (
      chatId: fixture.xiangqiSecondChatId,
      peerId: 200002,
      peer: xiangqiLightUser(200002, 'riverbend'),
    );
    final second = xiangqiConversationControllerProvider(secondKey);
    final secondListener = container.listen(second, (_, _) {});
    addTearDown(secondListener.close);
    await pumpEventQueue();
    harness.inbox.channel.fromServer(fixture.xiangqiMessagesFrame([]));
    await container.read(second.future);
    expect(await container.read(first.notifier).sendMessage('Same text'), isTrue);
    expect(await container.read(second.notifier).sendMessage('Same text'), isTrue);
    final firstOptimistic = container.read(first).requireValue.convo.messages.single;
    final secondOptimistic = container.read(second).requireValue.convo.messages.single;

    harness.inbox.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxMessageSentEvent, {
        'data': fixture.xiangqiMessageRow('Same text'),
      }),
    );
    await pumpEventQueue();
    expect(container.read(first).requireValue.convo.messages.single, firstOptimistic);
    expect(container.read(second).requireValue.convo.messages.single, secondOptimistic);
    expect(
      harness.inbox.emits.where((emit) => emit.event == kXiangqiInboxChatUserEvent),
      hasLength(3),
      reason: 'the first targeted resync must start instead of guessing from the text',
    );
    harness.inbox.channel.fromServer(fixture.xiangqiMessagesFrame([]));
    await pumpEventQueue();
    expect(
      harness.inbox.emits.where((emit) => emit.event == kXiangqiInboxChatUserEvent),
      hasLength(4),
      reason: 'both ambiguous conversations must be read through the serial no-ID queue',
    );
    harness.inbox.channel.fromServer(fixture.xiangqiMessagesFrame([]));
    await pumpEventQueue();
  });

  test('a lichess identity change shares history from the unchanged xiangqi session', () async {
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
    expect(
      harness.inbox.events.where((event) => event == kXiangqiInboxChatUserEvent),
      hasLength(1),
    );

    final current = await container.read(provider.future);
    expect(current.me.id, xiangqiUserId(fixture.xiangqiAccountId));
    expect(current.convo.messages.map((message) => message.text), ['Superseded history']);
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
