// Tests for the screen xiangqi.com's notifications are read on.
//
// The screen is driven over the same fake socket the online game screen's tests use: the list is a
// socket conversation and nothing else, so a test that wanted it over HTTP would be testing a
// request the app never makes.
//
// The frames are the shapes the 2026-10-16 probe measured — see `xiangqi-com-re/docs/social.md` —
// with every value replaced. Not one id, title or message here is the capture's.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart' show xiangqiAuthStorageProvider;
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
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
String notificationsFrame(List<Map<String, Object?>> items) =>
    fx.xiangqiEventFrame('get.notifications.success', {
      'data': {
        'notifications': {
          'items': items,
          'total_pages': 1,
          'has_next_page': false,
          'next_page_num': null,
          'prev_page_num': null,
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
Future<fx.FakeXiangqiChannelFactory> pumpNotifications(WidgetTester tester) async {
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
        xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((Ref ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWith(
          (ref) => fx.FakeXiangqiAuthStorage(
            fx.xiangqiTestSession(fx.xiangqiTestToken(fx.xiangqiTestViewerId)),
          ),
        ),
      },
    ),
  );

  // The client opens its channel from a chain of microtasks — the session restore, the token read,
  // the factory call, the connect frame — and a pump is what lets one of them run. Nothing in the
  // chain is a timer, so a generous number of pumps sees the whole of it.
  for (var pump = 0; pump < 30 && factory.channels.isEmpty; pump++) {
    await tester.pump();
  }
  expect(factory.channels, isNotEmpty, reason: 'the screen is expected to open a socket');
  factory.channel.fromServer(fx.openFrame);
  factory.channel.fromServer(fx.connectAckFrame);
  await settle(tester);
  return factory;
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
