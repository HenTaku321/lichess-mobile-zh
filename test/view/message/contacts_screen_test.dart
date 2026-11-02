// Tests for the merged contacts list.
//
// The list is the one screen where the two backends meet, so what is under test is that they meet in
// one list rather than two: that a lichess contact and a xiangqi conversation are both drawn, from
// one provider, in the merge's own order, and that each row opens its own conversation screen when
// tapped. The lichess side comes off the HTTP mock like every other server-backed test; the xiangqi
// side is a real socket protocol, so it is driven through the fixture's fake channel and the
// measured frames of a captured inbox session.
//
// The last group is the merge's failure rule, which is not a widget concern: a source that throws
// loses its own rows and nothing else, and only both throwing is the list an error. That rule is
// what keeps a backend's identity off the screen, so it is tested here rather than left to the
// screen to imply.

import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/message/conversation_screen.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';
import 'package:lichess_mobile/src/widgets/haptic_refresh_indicator.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/auth/fake_auth_storage.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The lichess inbox the screen is given, in the shape `/inbox` really answers with.
const lichessInboxJson = '''
{
  "me":{"name":"testUser","id":"testuser"},
  "contacts":[
    {"user":{"name":"chabrot","id":"chabrot"},"lastMsg":{"text":"a lichess message","user":"chabrot","date":1621533013388,"read":true}}
  ]
}
''';

/// The xiangqi conversation the screen is given, and the id its row opens.
///
/// The shape is the capture's; the ids are stand-ins.
const xiangqiChatId = 'qAAAAA';
const xiangqiPeerId = 200001;
const xiangqiPeerName = '棋友乙';

/// One `inbox.chats` row, in the shape the capture wrote.
const xiangqiChatRow = <String, Object?>{
  'chat_id': xiangqiChatId,
  'last_message': 'c',
  'last_seen': '2024-05-06T09:12:33.123456',
  'profile_image': null,
  'unread_messages': 0,
  'user_id': xiangqiPeerId,
  'username': xiangqiPeerName,
};

/// The `inbox.chats` frame carrying [xiangqiChatRow].
final xiangqiChatsFrame = fx.xiangqiEventFrame(kXiangqiInboxChatsEvent, {
  'data': {
    'has_next_page': false,
    'items': [xiangqiChatRow],
    'next_page_num': null,
    'prev_page_num': null,
    'total_pages': 1,
  },
});

/// [ContactsScreen] over a lichess inbox from the HTTP mock and a xiangqi chat list from the fake
/// socket. Returns the fake channel, so a test can play the server's half.
///
/// The socket and the repository are both built inside the tree's overrides rather than outside it,
/// so that the tree's own teardown closes them: a connected socket holds a ping watchdog timer, and
/// a timer still pending when the widget tree goes away fails the test. The repository is built on
/// that same socket because its spacing has to be zero here — the chat list is the only request this
/// screen makes, and a test that waited out the real 1.5 s window would be testing the clock rather
/// than the list.
Future<fx.FakeXiangqiChannelFactory> pumpScreen(
  WidgetTester tester, {
  bool pushRoute = false,
  bool holdXiangqi = false,
  MockClient? client,
  String? initialChatsFrame,
}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final token = fx.xiangqiTestToken(fx.xiangqiTestViewerId);
  final storage = fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token));

  final mockClient =
      client ??
      MockClient((request) {
        if (request.url.path == '/inbox') {
          return mockResponse(lichessInboxJson, 200);
        }
        if (request.url.path == '/inbox/search') {
          return mockResponse(
            '''{"contacts":[{"user":{"name":"chabrot","id":"chabrot"},"lastMsg":{"text":"a lichess message","user":"chabrot","date":1621533013388,"read":true}}],"friends":[],"users":[]}''',
            200,
          );
        }
        return mockResponse('', 404);
      });

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: pushRoute
          ? Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(ContactsScreen.buildRoute()),
                child: const Text('Open inbox'),
              ),
            )
          : const ContactsScreen(),
      authUser: fakeAuthUser,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => mockClient),
        ),
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          final socket = XiangqiSocketClient(channelFactory: factory, getToken: () async => token);
          ref.onDispose(socket.dispose);
          return socket;
        }),
        xiangqiInboxRepositoryProvider: xiangqiInboxRepositoryProvider.overrideWith((Ref ref) {
          final repository = XiangqiInboxRepository(
            socket: ref.watch(xiangqiSocketProvider),
            storage: ref.watch(xiangqiAuthStorageProvider),
            spacing: Duration.zero,
          );
          ref.onDispose(repository.dispose);
          return repository;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(storage),
      },
    ),
  );

  if (pushRoute) {
    await tester.tap(find.text('Open inbox'));
    await tester.pump();
    await tester.pump();
  }

  // The chat list is asked for by the first read of the provider, which is the socket's own
  // handshake's cue; the server's half of it is pushed here.
  await pumpUntil(
    tester,
    () => factory.channels.isNotEmpty && factory.channel.sentConnect,
    reason: 'the contacts screen is expected to open a xiangqi socket',
  );
  final channel = factory.channel;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);
  await pumpUntil(
    tester,
    () => channel.hasSentEvent(kXiangqiInboxJoinEvent),
    reason: 'the chat list is expected to be asked for once the socket is open',
  );
  if (!holdXiangqi) {
    channel.fromServer(initialChatsFrame ?? xiangqiChatsFrame);
    await tester.pumpAndSettle();
  } else {
    for (var pump = 0; pump < 20; pump++) {
      await tester.pump();
    }
  }

  return factory;
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('desktop contacts expose the same explicit refresh affordance as other lists', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(DesktopRefreshButton), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('inserting rows from one contacts source preserves the visible other-source anchor', (
    tester,
  ) async {
    var refreshed = false;
    final rows = [
      for (var index = 0; index < 40; index++)
        {
          ...xiangqiChatRow,
          'chat_id': 'anchor-chat-$index',
          'user_id': 200001 + index,
          'username': 'Peer $index',
        },
    ];
    final frame = fx.xiangqiEventFrame(kXiangqiInboxChatsEvent, {
      'data': {'items': rows, 'has_next_page': false, 'total_pages': 1},
    });
    final factory = await pumpScreen(
      tester,
      initialChatsFrame: frame,
      client: MockClient((request) {
        if (request.url.path != '/inbox') return mockResponse('', 404);
        if (!refreshed) return mockResponse(lichessInboxJson, 200);
        final body = jsonDecode(lichessInboxJson) as Map<String, dynamic>;
        body['contacts'] = [
          for (var index = 0; index < 2; index++)
            {
              'user': {'name': 'New contact $index', 'id': 'new-contact-$index'},
              'lastMsg': {
                'text': index == 0
                    ? 'Short message'
                    : 'A longer message that wraps across several lines ' * 3,
                'user': 'new-contact-$index',
                'date': 1621533013388,
                'read': true,
              },
            },
          ...(body['contacts']! as List<dynamic>),
        ];
        return mockResponse(jsonEncode(body), 200);
      }),
    );
    final anchor = find.text('Peer 8');
    await tester.scrollUntilVisible(
      anchor,
      200,
      scrollable: find
          .descendant(of: find.byType(ContactsListView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.ensureVisible(anchor);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(anchor).dy;
    refreshed = true;
    final refresh = tester
        .widget<HapticRefreshIndicator>(find.byType(HapticRefreshIndicator))
        .onRefresh();
    await tester.pump();
    await tester.pump();
    factory.channel.fromServer(frame);
    await refresh;
    await tester.pumpAndSettle();
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a healthy contacts source is visible while the other source is still loading', (
    tester,
  ) async {
    final factory = await pumpScreen(tester, holdXiangqi: true);
    final container = ProviderScope.containerOf(tester.element(find.byType(ContactsScreen)));
    await pumpUntil(
      tester,
      () => container.read(lichessContactsProvider).hasValue,
      reason: 'the HTTP source must settle before checking independent rendering',
    );
    expect(find.text('chabrot'), findsOneWidget);
    factory.channel.fromServer(xiangqiChatsFrame);
    await tester.pumpAndSettle();
    expect(find.text(xiangqiPeerName), findsOneWidget);
  });

  testWidgets('a failed source is visible as a local retry without hiding healthy contacts', (
    tester,
  ) async {
    final factory = await pumpScreen(tester, holdXiangqi: true);
    final container = ProviderScope.containerOf(tester.element(find.byType(ContactsScreen)));
    await pumpUntil(
      tester,
      () => container.read(lichessContactsProvider).hasValue,
      reason: 'the healthy HTTP source must settle before the socket is disconnected',
    );
    factory.channel.fromServer('41/xiangqi,');
    await tester.pump(const Duration(seconds: 21));
    for (var pump = 0; pump < 20; pump++) {
      await tester.pump();
    }
    final context = tester.element(find.byType(ContactsScreen));
    expect(find.text('chabrot'), findsOneWidget);
    expect(find.text(context.l10n.mobileSomethingWentWrong), findsAtLeastNWidgets(1));
    expect(find.byTooltip(context.l10n.retry), findsAtLeastNWidgets(1));
  });

  testWidgets('the merged contacts list can append the second xiangqi page', (tester) async {
    final factory = await pumpScreen(tester, holdXiangqi: true);
    factory.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxChatsEvent, {
        'data': {
          'items': [xiangqiChatRow],
          'total_pages': 2,
          'next_page_num': 2,
          'prev_page_num': null,
          'has_next_page': true,
        },
      }),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ContactsScreen));
    final more = find.text(context.l10n.mobileLoadMore);
    expect(more, findsOneWidget);
    await tester.tap(more);
    for (var pump = 0; pump < 20; pump++) {
      await tester.pump();
    }
    expect(find.text('chabrot'), findsOneWidget);
    expect(find.text(xiangqiPeerName), findsOneWidget);
    expect(
      factory.channel.sent.whereType<String>().any(
        (frame) => frame.contains('inbox.join') && frame.contains('"page":2'),
      ),
      isTrue,
    );
    factory.channel.fromServer(
      fx.xiangqiEventFrame(kXiangqiInboxChatsEvent, {
        'data': {
          'items': [
            {
              ...xiangqiChatRow,
              'chat_id': 'second-chat',
              'user_id': 200002,
              'username': 'Second peer',
            },
          ],
          'total_pages': 2,
          'next_page_num': null,
          'prev_page_num': 1,
          'has_next_page': false,
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Second peer'), findsOneWidget);
    expect(find.text(xiangqiPeerName), findsOneWidget);
    expect(more, findsNothing);
  });

  group('ContactsScreen merged list', () {
    testWidgets('an account change clears the query and cancels the previous debounced search', (
      tester,
    ) async {
      await pumpScreen(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(ContactsScreen)));
      await tester.enterText(find.byType(TextField), 'chab');
      await container
          .read(xiangqiSessionStoreProvider)
          .write(
            fx.xiangqiTestSession(fx.xiangqiTestToken('900001'), userId: '900001', isGuest: false),
          );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(tester.widget<PlatformSearchBar>(find.byType(PlatformSearchBar)).controller!.text, '');
      expect(container.read(messageSearchQueryProvider), '');
    });

    testWidgets('renewing the same account token preserves its query', (tester) async {
      await pumpScreen(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(ContactsScreen)));
      await tester.enterText(find.byType(TextField), 'chab');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final store = container.read(xiangqiSessionStoreProvider);
      await store.write(store.current!.copyWith(accessToken: 'renewed-token'));
      await tester.pump();
      expect(
        tester.widget<PlatformSearchBar>(find.byType(PlatformSearchBar)).controller!.text,
        'chab',
      );
      expect(container.read(messageSearchQueryProvider), 'chab');
    });

    testWidgets('a rapid second click does not push a duplicate conversation route', (
      tester,
    ) async {
      final factory = await pumpScreen(tester);
      // Exercise reentrant activation of the actual row callback before the next frame disables
      // the covered route. A pair of pointer/keyboard activations must not create two pages.
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(xiangqiPeerName), matching: find.byType(ListTile)),
      );
      tile.onTap!();
      tile.onTap!();
      await pumpUntil(tester, () => factory.channel.hasSentEvent(kXiangqiInboxChatUserEvent));
      factory.channel.fromServer(
        fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, {
          'data': {
            'has_next_page': false,
            'items': <Object?>[],
            'next_page_num': null,
            'prev_page_num': null,
            'total_pages': 1,
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(XiangqiConversationScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('returning from a conversation preserves the current search query', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'chab');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(ContactTile), findsOneWidget);
      await tester.tap(find.text('chabrot'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<PlatformSearchBar>(find.byType(PlatformSearchBar)).controller!.text,
        'chab',
      );
      expect(find.byType(ContactTile), findsOneWidget);
    });

    testWidgets('a removed contacts route is not refreshed when its conversation later closes', (
      tester,
    ) async {
      await pumpScreen(tester, pushRoute: true);
      final contactsContext = tester.element(find.byType(ContactsScreen));
      final contactsRoute = ModalRoute.of(contactsContext)!;
      final navigator = Navigator.of(contactsContext);
      final search = tester.widget<PlatformSearchBar>(find.byType(PlatformSearchBar));
      await tester.tap(find.text('chabrot'));
      await tester.pumpAndSettle();
      navigator.removeRoute(contactsRoute);
      await tester.pump();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open inbox'), findsOneWidget);
      expect(() => search.controller!.addListener(() {}), throwsFlutterError);
      expect(() => search.focusNode!.addListener(() {}), throwsFlutterError);
    });

    testWidgets('draws both backends rows from one list, lichess first as the merge orders them', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Both rows exist: neither backend's conversations are dropped any more.
      expect(find.text('chabrot'), findsOneWidget);
      expect(find.text(xiangqiPeerName), findsOneWidget);
      expect(find.text('a lichess message'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);

      // The lichess row is the upper one, because the merge appends the xiangqi source's rows after
      // the lichess ones and the list renders its own order rather than re-sorting it.
      final lichessRow = tester.getTopLeft(find.text('chabrot')).dy;
      final xiangqiRow = tester.getTopLeft(find.text(xiangqiPeerName)).dy;
      expect(lichessRow, lessThan(xiangqiRow));
    });

    testWidgets('tapping the xiangqi row opens the xiangqi conversation', (tester) async {
      final factory = await pumpScreen(tester);

      expect(find.byType(XiangqiConversationScreen), findsNothing);

      await tester.tap(find.text(xiangqiPeerName));
      await tester.pump();
      await tester.pump();

      expect(find.byType(XiangqiConversationScreen), findsOneWidget);
      expect(find.byType(ConversationScreen), findsNothing);
      final screen = tester.widget<XiangqiConversationScreen>(
        find.byType(XiangqiConversationScreen),
      );
      expect(screen.chatId, xiangqiChatId);
      expect(screen.peerId, xiangqiPeerId);
      expect(screen.peer.name, xiangqiPeerName);

      // The screen asks for the conversation's first page on open, and the server's half of that is
      // pushed here. This also exercises the controller's second build: it watches the app's auth
      // state, which lands after the first, and a controller that initialised itself only once would
      // fail on that second build rather than draw the page.
      final channel = factory.channel;
      await pumpUntil(
        tester,
        () => channel.hasSentEvent(kXiangqiInboxChatUserEvent),
        reason: 'opening the conversation is expected to ask for its first page',
      );
      channel.fromServer(
        fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, {
          'data': {
            'has_next_page': false,
            'items': [
              {
                'created_on': '2024-05-06T09:12:33.123456',
                'message': 'c',
                'read': false,
                'sender_id': xiangqiPeerId,
              },
            ],
            'next_page_num': null,
            'prev_page_num': null,
            'total_pages': 1,
          },
        }),
      );
      await tester.pumpAndSettle();

      // The inline timestamp spacer contributes a placeholder to Text.rich's plain text.
      expect(
        find.byWidgetPredicate((widget) => widget is RichLinkText && widget.text == 'c'),
        findsOneWidget,
      );
      // The page is drawn, not an error state: a controller that initialised itself only on its
      // first build would have failed here.
      expect(find.textContaining('LateInitializationError'), findsNothing);
    });

    testWidgets('tapping the lichess row still opens the lichess conversation', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('chabrot'));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.byType(XiangqiConversationScreen), findsNothing);
    });
  });

  group('contactsProvider merge', () {
    /// A container whose lichess inbox is [inbox] and whose xiangqi source is [xiangqi].
    Future<ProviderContainer> makeMergeContainer({
      required MockClient inbox,
      required Future<IList<Contact>> Function(Ref ref) xiangqi,
    }) {
      return makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(() => inbox),
          ),
          xiangqiContactsProvider: xiangqiContactsProvider.overrideWith((ref) => xiangqi(ref)),
        },
      );
    }

    test('one source failing loses its own rows and not the list', () async {
      // The xiangqi source is down; the lichess inbox answers.
      final container = await makeMergeContainer(
        inbox: MockClient((request) => mockResponse(lichessInboxJson, 200)),
        xiangqi: (ref) => Future.error(StateError('xiangqi is down')),
      );

      final contacts = await container.read(contactsProvider.future);

      expect(contacts.contacts.map((c) => c.user.name), ['chabrot']);
      expect(contacts.me.name, 'testUser');
    });

    test('the other source failing loses only its own rows', () async {
      // The lichess inbox is down; the xiangqi chat list answers.
      final container = await makeMergeContainer(
        inbox: MockClient((request) => mockResponse('', 500)),
        xiangqi: (ref) async => xiangqiContactsFromChats(const {
          'data': {
            'items': [xiangqiChatRow],
          },
        }),
      );

      final contacts = await container.read(contactsProvider.future);

      expect(contacts.contacts.map((c) => c.user.name), [xiangqiPeerName]);
      // `me` is a scalar and is not merged: with no lichess inbox to read it from, it falls back to
      // the lichess account the app already knows, and never to a xiangqi identity blended in.
      expect(contacts.me.name, 'testUser');
    });

    test('only both sources failing is a failure of the list', () async {
      final container = await makeMergeContainer(
        inbox: MockClient((request) => mockResponse('', 500)),
        xiangqi: (ref) => Future.error(StateError('xiangqi is down')),
      );

      await expectLater(container.read(contactsProvider.future), throwsA(isA<ServerException>()));
    });
  });
}
