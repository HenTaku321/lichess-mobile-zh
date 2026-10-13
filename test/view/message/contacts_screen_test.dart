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

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/message/message.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/message/conversation_screen.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';

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
const xiangqiChatId = 'qAG5KR';
const xiangqiPeerId = 487593;
const xiangqiPeerName = '象棋高手阿豹';

/// One `inbox.chats` row, exactly as the capture wrote it.
const xiangqiChatRow = <String, Object?>{
  'chat_id': xiangqiChatId,
  'last_message': 'c',
  'last_seen': '2026-08-30T04:42:25.594449',
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
Future<fx.FakeXiangqiChannelFactory> pumpScreen(WidgetTester tester) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final token = fx.xiangqiTestToken(fx.xiangqiTestViewerId);
  final storage = fx.FakeXiangqiAuthStorage(fx.xiangqiTestSession(token));

  final mockClient = MockClient((request) {
    if (request.url.path == '/inbox') {
      return mockResponse(lichessInboxJson, 200);
    }
    return mockResponse('', 404);
  });

  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const ContactsScreen(),
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

  // The chat list is asked for by the first read of the provider, which is the socket's own
  // handshake's cue; the server's half of it is pushed here.
  await tester.pump();
  await tester.runAsync(() async {
    await pumpEventQueue();
    factory.channel.fromServer(fx.openFrame);
    factory.channel.fromServer(fx.connectAckFrame);
    await pumpEventQueue();
    factory.channel.fromServer(xiangqiChatsFrame);
    await pumpEventQueue();
  });
  await tester.pumpAndSettle();

  return factory;
}

void main() {
  TestLichessBinding.ensureInitialized();

  group('ContactsScreen merged list', () {
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
      await tester.runAsync(() async {
        await pumpEventQueue();
        factory.channel.fromServer(
          fx.xiangqiEventFrame(kXiangqiInboxUserMessagesEvent, {
            'data': {
              'has_next_page': false,
              'items': [
                {
                  'created_on': '2026-08-30T04:42:25.594449',
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
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();

      expect(find.text('c'), findsWidgets);
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
