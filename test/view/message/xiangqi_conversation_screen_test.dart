import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/socket.dart' show webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/message/xiangqi_inbox_repository_test.dart' as fixture;
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

Future<ProviderContainer> pumpConversation(WidgetTester tester) async {
  final factory = fx.FakeXiangqiChannelFactory();
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: XiangqiConversationScreen(
        chatId: fixture.xiangqiFirstChatId,
        peerId: fixture.xiangqiFirstPeerId,
        peer: xiangqiLightUser('${fixture.xiangqiFirstPeerId}', fixture.xiangqiFirstPeerName),
      ),
      overrides: {
        webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(factory),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(signedInSession.copyWith(userId: fixture.xiangqiAccountId)),
        ),
        xiangqiInboxRepositoryProvider: xiangqiInboxRepositoryProvider.overrideWith((ref) {
          final repository = XiangqiInboxRepository(
            socket: ref.watch(xiangqiSocketProvider),
            storage: ref.watch(xiangqiAuthStorageProvider),
            sessionStore: ref.read(xiangqiSessionStoreProvider),
            spacing: Duration.zero,
          );
          ref.onDispose(repository.dispose);
          return repository;
        }),
      },
    ),
  );
  await pumpUntil(
    tester,
    () => factory.channels.isNotEmpty && factory.channel.sentConnect,
    reason: 'the conversation screen is expected to open a socket',
  );
  final channel = factory.channel;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);
  await pumpUntil(
    tester,
    () => channel.hasSentEvent(kXiangqiInboxChatUserEvent),
    reason: 'the open conversation is expected to ask for its first page',
  );
  channel.fromServer(
    fixture.xiangqiMessagesFrame([
      fixture.xiangqiMessageRow('Hello', senderId: fixture.xiangqiFirstPeerId),
    ]),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(XiangqiConversationScreen)));
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('failed PM sending retains the draft and rolls back the optimistic bubble', (
    tester,
  ) async {
    final container = await pumpConversation(tester);
    container.read(xiangqiInboxRepositoryProvider).dispose();
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Keep this draft');
    final key = (
      chatId: fixture.xiangqiFirstChatId,
      peerId: fixture.xiangqiFirstPeerId,
      peer: xiangqiLightUser('${fixture.xiangqiFirstPeerId}', fixture.xiangqiFirstPeerName),
    );
    expect(
      container
          .read(xiangqiConversationControllerProvider(key))
          .requireValue
          .convo
          .messages
          .where((message) => message.text == 'Keep this draft'),
      isEmpty,
    );
  });

  testWidgets('signing out removes the composer and its previous account draft', (tester) async {
    final container = await pumpConversation(tester);
    await tester.enterText(find.byType(TextField), 'Account A draft');
    await container.read(xiangqiSessionStoreProvider).write(null);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Account A draft'), findsNothing);
  });

  testWidgets('desktop PM refresh retains the composer draft and already loaded messages', (
    tester,
  ) async {
    await pumpConversation(tester);
    await tester.enterText(find.byType(TextField), 'Keep this PM draft');
    final loadedMessage = find.byWidgetPredicate(
      (widget) => widget is RichLinkText && widget.text == 'Hello',
    );
    expect(loadedMessage, findsOneWidget);
    expect(find.byType(DesktopRefreshButton), findsOneWidget);
    await tester.tap(find.byType(DesktopRefreshButton));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Keep this PM draft');
    expect(loadedMessage, findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
