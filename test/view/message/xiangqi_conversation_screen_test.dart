import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart' show webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/message/xiangqi_inbox_repository_test.dart' as fixture;
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

Future<ProviderContainer> pumpConversation(
  WidgetTester tester, {
  MockClient? httpClient,
  bool hiddenUsername = false,
  fx.FakeXiangqiChannelFactory? channelFactory,
  Map<String, Object?>? firstPage,
}) async {
  final factory = channelFactory ?? fx.FakeXiangqiChannelFactory();
  final contact = xiangqiContactsFromChats(
    fixture.xiangqiPagePayload([
      {...fixture.xiangqiFirstChatRow, 'hidden_username': hiddenUsername},
    ]),
  ).single;
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: XiangqiConversationScreen(
        chatId: fixture.xiangqiFirstChatId,
        peerId: fixture.xiangqiFirstPeerId,
        peer: contact.user,
        peerProfileAvailable: contact.xiangqi!.peerProfileAvailable,
      ),
      overrides: {
        if (httpClient != null)
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (_) => FakeHttpClientFactory(() => httpClient),
          ),
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
    firstPage == null
        ? fixture.xiangqiMessagesFrame([
            fixture.xiangqiMessageRow('Hello', senderId: fixture.xiangqiFirstPeerId),
          ])
        : fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, firstPage),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(XiangqiConversationScreen)));
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('a peer push preserves the older message currently being read', (tester) async {
    final factory = fx.FakeXiangqiChannelFactory();
    await pumpConversation(
      tester,
      channelFactory: factory,
      firstPage: fixture.xiangqiPagePayload([
        for (var index = 0; index < 40; index++)
          fixture.xiangqiMessageRow(
            'Message $index',
            senderId: fixture.xiangqiFirstPeerId,
            createdOn: '2024-05-06T09:12:${(39 - index).toString().padLeft(2, '0')}.123456',
          ),
      ]),
    );
    final anchor = find.byWidgetPredicate((w) => w is RichLinkText && w.text == 'Message 12');
    await tester.scrollUntilVisible(anchor, 200);
    await tester.ensureVisible(anchor);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(anchor).dy;
    factory.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxMessageSentEvent, {
        'data': fixture.xiangqiMessageRow(
          'A newly arrived message with a different height. ' * 3,
          senderId: fixture.xiangqiFirstPeerId,
          createdOn: '2024-05-06T09:12:59.123456',
        ),
      }),
    );
    await tester.pumpAndSettle();
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
  });

  testWidgets('older PM pages are reachable without replacing messages or the focused draft', (
    tester,
  ) async {
    final factory = fx.FakeXiangqiChannelFactory();
    await pumpConversation(
      tester,
      channelFactory: factory,
      firstPage: {
        'data': {
          ...fixture.xiangqiPagePayload([
                fixture.xiangqiMessageRow('Newest', senderId: fixture.xiangqiFirstPeerId),
              ])['data']!
              as Map<String, Object?>,
          'has_next_page': true,
          'next_page_num': 2,
          'total_pages': 2,
        },
      },
    );
    await tester.enterText(find.byType(TextField), 'Unsent draft');
    final field = tester.widget<TextField>(find.byType(TextField));
    final focused = FocusManager.instance.primaryFocus;
    final context = tester.element(find.byType(XiangqiConversationScreen));
    final more = find.text(context.l10n.mobileLoadMore);
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pump();
    expect(factory.channel.sent.last.toString(), contains('"page":2'));
    factory.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, {
        'data': {
          ...fixture.xiangqiPagePayload([
                fixture.xiangqiMessageRow(
                  'Older',
                  senderId: fixture.xiangqiFirstPeerId,
                  createdOn: '2024-05-05T08:41:19.333333',
                ),
              ])['data']!
              as Map<String, Object?>,
          'prev_page_num': 1,
          'total_pages': 2,
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is RichLinkText && w.text == 'Newest'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RichLinkText && w.text == 'Older'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller, same(field.controller));
    expect(field.controller!.text, 'Unsent draft');
    expect(FocusManager.instance.primaryFocus, same(focused));
    expect(more, findsNothing);
  });

  testWidgets('a hidden inbox username remains readable but never becomes a profile target', (
    tester,
  ) async {
    await pumpConversation(tester, hiddenUsername: true);
    final title = tester.widget<ListTile>(
      find.ancestor(of: find.text(fixture.xiangqiFirstPeerName), matching: find.byType(ListTile)),
    );
    expect(title.onTap, isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a visible PM peer name opens the xiangqi profile and preserves the conversation draft',
    (tester) async {
      await pumpConversation(
        tester,
        httpClient: MockClient((_) async => http.Response('{"items":[]}', 200)),
      );
      await tester.enterText(find.byType(TextField), 'Draft before profile');
      await tester.tap(find.text(fixture.xiangqiFirstPeerName));
      await tester.pump();
      final profile = find.byType(XiangqiProfileScreen, skipOffstage: false);
      expect(profile, findsOneWidget);
      expect(tester.widget<XiangqiProfileScreen>(profile).username, fixture.xiangqiFirstPeerName);
      final context = tester.element(profile);
      final route = ModalRoute.of(context)!;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 1600));
      }
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(route.reverseTransitionDuration + const Duration(milliseconds: 50));
      expect(find.byType(XiangqiConversationScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft before profile',
      );
      expect(tester.takeException(), isNull);
    },
  );

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
