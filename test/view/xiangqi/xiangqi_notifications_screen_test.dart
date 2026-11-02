// Tests for the screen xiangqi.com's notifications are read on.
//
// The screen is driven over the same fake socket the online game screen's tests use: the list is a
// socket conversation and nothing else, so a test that wanted it over HTTP would be testing a
// request the app never makes.
//
// The frames are the shapes the 2026-10-16 probe measured — see `xiangqi-com-re/docs/social.md` —
// with every value replaced. Not one id, title or message here is the capture's.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lessons_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

/// One notification, with the fields the socket was measured to carry.
Map<String, Object?> notification({
  int id = 1,
  String title = 'A title',
  String message = 'A body',
  String? url = '/leaders',
  bool isRead = false,
}) => {
  'id': id,
  'type': 2,
  'title': title,
  'msg': message,
  'url': url,
  'is_read': isRead,
  'created_on': '2026-10-15T14:05:20.215677',
  'sender_id': null,
  'username': null,
  'profile_image': null,
  'profile_link_token': null,
  'hidden_username': false,
  'hidden_profile_icon': false,
};

/// The `get.notifications.success` frame for [items].
String notificationsFrame(
  List<Map<String, Object?>> items, {
  int totalPages = 1,
  int? nextPage,
  int? previousPage,
}) => fx.xiangqiEventFrame('get.notifications.success', {
  'data': {
    'notifications': {
      'items': items,
      'total_pages': totalPages,
      'has_next_page': nextPage != null,
      'next_page_num': nextPage,
      'prev_page_num': previousPage,
    },
  },
});

/// Pumps until nothing more is coming.
///
/// Generously, because the chain is long: the session is restored from storage, the socket is
/// opened, the connect ack is read, the request goes out, the answer is parsed — and a mark-all adds
/// a second pass of the same. Nothing in it is a timer, so a pump is what lets one link run, and the
/// loop is here so that a test does not depend on how many.
Future<void> settle(WidgetTester tester, {int rounds = 60}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.pump();
  }
}

/// Opens the notifications screen over a fake socket, and hands the factory back.
Future<fx.FakeXiangqiChannelFactory> pumpNotifications(
  WidgetTester tester, {
  MockClient? httpClient,
}) async {
  final factory = fx.FakeXiangqiChannelFactory();
  final client = XiangqiSocketClient(
    channelFactory: factory,
    getToken: () async => fx.xiangqiTestToken(fx.xiangqiTestViewerId),
  );
  addTearDown(client.dispose);

  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: XiangqiNotificationsScreen(),
      ),
      overrides: {
        if (httpClient != null)
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (_) => FakeHttpClientFactory(() => httpClient),
          ),
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(
            // A real account: notifications are the one thing on the socket a guest is not given —
            // the server disconnects the namespace rather than answering.
            fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId), isGuest: false),
          ),
        ),
      },
    ),
  );

  // The client opens its channel from a chain of microtasks — the session restore, the token read,
  // the factory call, the connect frame — and a pump is what lets one of them run. Nothing in the
  // chain is a timer, so a generous number of pumps sees the whole of it.
  final handshaken = <fx.FakeXiangqiChannel>{};
  for (var pump = 0; pump < 80; pump++) {
    await tester.pump();
    for (final channel in factory.channels.toList()) {
      if (!channel.closed && channel.sentConnect && handshaken.add(channel)) {
        channel.fromServer(fx.openFrame);
        channel.fromServer(fx.connectAckFrame);
      }
    }
    if (factory.channels.isNotEmpty && factory.channel.hasSentEvent('get.notifications')) break;
  }
  expect(factory.channels, isNotEmpty, reason: 'the screen is expected to open a socket');
  expect(
    factory.channel.hasSentEvent('get.notifications'),
    isTrue,
    reason: 'the live channel must have sent its page request before the fixture replies',
  );
  await settle(tester);
  return factory;
}

/// Observe the actual URL handed to the platform without opening a browser.
List<String> recordNotificationLaunches(WidgetTester tester, {bool fail = false}) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      final arguments = call.arguments as Map<Object?, Object?>;
      launches.add(arguments['url']! as String);
      if (fail) throw PlatformException(code: 'cannot-open');
      return true;
    }
    return false;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return launches;
}

/// The action that marks everything read.
///
/// Found by its tooltip and then by the button *above* it: an `IconButton` builds its own tooltip
/// around its child, so the tooltip is inside the button rather than the other way round.
IconButton markAllReadButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(of: find.byTooltip('Mark all read'), matching: find.byType(IconButton)),
);

void main() {
  TestLichessBinding.ensureInitialized();

  group('XiangqiNotificationsScreen', () {
    testWidgets('notifications do not connect the shared socket', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification()]));
      await settle(tester);
      expect(find.text('A title'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(XiangqiNotificationsScreen)),
      );
      expect(
        container.read(xiangqiSocketProvider).isConnected,
        isFalse,
        reason: 'notifications must own an independent transport',
      );
    });

    testWidgets('loads the next notification page and retains the first page', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(
        notificationsFrame([notification(title: 'First page')], totalPages: 2, nextPage: 2),
      );
      await settle(tester);
      final context = tester.element(find.byType(XiangqiNotificationsScreen));
      final more = find.text(context.l10n.mobileLoadMore);
      expect(more, findsOneWidget, reason: 'the server next-page cursor must be reachable');

      await tester.tap(more);
      await settle(tester);
      expect(find.text('First page'), findsOneWidget);
      expect(
        factory.channel.sent.whereType<String>().any(
          (frame) => frame.contains('get.notifications') && frame.contains('"page":2'),
        ),
        isTrue,
      );
      factory.channel.fromServer(
        notificationsFrame(
          [notification(id: 2, title: 'Second page')],
          totalPages: 2,
          previousPage: 1,
        ),
      );
      await settle(tester);
      expect(find.text('First page'), findsOneWidget);
      expect(find.text('Second page'), findsOneWidget);
      expect(more, findsNothing);
    });

    for (final url in ['/leaders', '/leaders/puzzle/CN']) {
      testWidgets('notification $url opens the native leaderboard once and returns to the list', (
        tester,
      ) async {
        final launches = recordNotificationLaunches(tester);
        final requests = <http.Request>[];
        final factory = await pumpNotifications(
          tester,
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{"meta":{"total_pages":0,"total_players":0,"current_page":1},"data":[]}',
              200,
            );
          }),
        );
        factory.channel.fromServer(
          notificationsFrame([notification(title: 'Open leaders', url: url)]),
        );
        await settle(tester);
        await tester.tap(find.text('Open leaders'));
        await tester.tap(find.text('Open leaders'));
        await tester.pumpAndSettle();
        expect(find.byType(XiangqiLeaderboardScreen, skipOffstage: false), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 1600));
        }
        final lookups = requests
            .where((request) => request.url.path == '/api/leaders/v2/list')
            .toList();
        expect(lookups, hasLength(1));
        expect(lookups.single.url.queryParameters['mode'], url == '/leaders' ? 'rapid' : 'puzzle');
        expect(lookups.single.url.queryParameters['country'], url == '/leaders' ? null : 'CN');
        expect(launches, isEmpty);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(XiangqiNotificationsScreen), findsOneWidget);
        expect(find.text('Open leaders'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a lesson topic notification keeps its exact topic in the native app', (
      tester,
    ) async {
      final launches = recordNotificationLaunches(tester);
      final factory = await pumpNotifications(
        tester,
        httpClient: MockClient((_) async => http.Response('{}', 503)),
      );
      factory.channel.fromServer(
        notificationsFrame([
          notification(
            title: 'Open lesson',
            url: 'https://play.xiangqi.com/lessons/topic/Topic123',
          ),
        ]),
      );
      await settle(tester);
      await tester.tap(find.text('Open lesson'));
      await tester.pump();
      final screen = find.byType(XiangqiTopicScreen, skipOffstage: false);
      expect(screen, findsOneWidget);
      expect(tester.widget<XiangqiTopicScreen>(screen).topicId, 'Topic123');
      expect(launches, isEmpty);
      // Dispose the failed lookup before its retry timer can schedule another request.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('unsupported query and fragment are preserved when a notification opens outside', (
      tester,
    ) async {
      final launches = recordNotificationLaunches(tester);
      const url = '/leaders?note=a%2Fb&return=%2Fplay#weekly';
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification(title: 'Keep URL', url: url)]));
      await settle(tester);
      await tester.tap(find.text('Keep URL'));
      await tester.pump();
      expect(launches, ['https://play.xiangqi.com$url']);
      expect(find.byType(XiangqiLeaderboardScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final url in [
      'javascript:alert(1)',
      'data:text/plain,not-a-page',
      'file:///project.txt',
    ]) {
      testWidgets('notification $url is readable but not an active platform link', (tester) async {
        final launches = recordNotificationLaunches(tester);
        final factory = await pumpNotifications(tester);
        factory.channel.fromServer(
          notificationsFrame([notification(title: 'No action', url: url)]),
        );
        await settle(tester);
        final row = tester.widget<ListTile>(
          find.ancestor(of: find.text('No action'), matching: find.byType(ListTile)),
        );
        expect(row.onTap, isNull);
        expect(launches, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a lookalike host stays external instead of opening a xiangqi screen', (
      tester,
    ) async {
      final launches = recordNotificationLaunches(tester);
      const url = 'https://play.xiangqi.com.example.invalid/leaders';
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification(title: 'External', url: url)]));
      await settle(tester);
      await tester.tap(find.text('External'));
      await tester.pump();
      expect(launches, [url]);
      expect(find.byType(XiangqiLeaderboardScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed platform launch stays on the notification list without an async error', (
      tester,
    ) async {
      recordNotificationLaunches(tester, fail: true);
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(
        notificationsFrame([
          notification(title: 'Cannot open', url: 'https://example.invalid/article'),
        ]),
      );
      await settle(tester);
      await tester.tap(find.text('Cannot open'));
      await tester.pump();
      expect(find.text('Cannot open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists what the server sent, with its title and its body', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(
        notificationsFrame([
          notification(id: 1, title: 'First', message: 'One'),
          notification(id: 2, title: 'Second', message: 'Two', isRead: true),
        ]),
      );
      await settle(tester);

      expect(find.text('First'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('says so when there is nothing', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame(const []));
      await settle(tester);

      expect(find.text('No notifications.'), findsOneWidget);
    });

    testWidgets('offers nothing to mark when everything is already read', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification(id: 1, isRead: true)]));
      await settle(tester);

      expect(markAllReadButton(tester).onPressed, isNull);
    });

    testWidgets('offers to mark everything read while something is unread', (tester) async {
      // Two tests rather than one screen pushed twice through two frames: a provider that has
      // already answered is not re-read because another frame arrived, so the second state has to
      // be its own screen.
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification(id: 1)]));
      await settle(tester);

      expect(markAllReadButton(tester).onPressed, isNotNull);
    });

    testWidgets('marks everything read over the socket, and asks again', (tester) async {
      final factory = await pumpNotifications(tester);
      factory.channel.fromServer(notificationsFrame([notification(id: 1)]));
      await settle(tester);

      await tester.tap(find.byTooltip('Mark all read'));
      await settle(tester);

      // The event went out under the name the client sends, and the screen waited for the name the
      // server really answers with — `mark.all.notif.read.success`, one word shorter than the
      // shipped bundle spells it.
      final sent = factory.channel.sent.whereType<String>().toList();
      expect(
        sent.any((frame) => frame.contains('mark.all.notifications.read')),
        isTrue,
        reason: 'the mark-all event should have gone out',
      );

      // The answer is what ends the wait; without it the button stays spent.
      factory.channel.fromServer(fx.xiangqiEventFrame('mark.all.notif.read.success', null));
      await settle(tester);

      // And the list is asked for again, which is what makes the rows draw as read. Read afresh
      // rather than off the list taken before the answer: the second request is made *because* of
      // that answer.
      final after = factory.channel.sent.whereType<String>().toList();
      expect(
        after.where((frame) => frame.contains('get.notifications')).length,
        greaterThan(1),
        reason: 'the list should have been asked for a second time',
      );
    });
  });
}
