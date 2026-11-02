import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_session.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import 'xiangqi_analysis_exit_contract_test.dart' as routes;
import 'xiangqi_chat_screen_test.dart' as chat;

Future<chat.FakeChatChannel> openLoadedRoom(
  WidgetTester tester,
  chat.FakeChatChannelFactory factory,
  String name,
) async {
  await tester.tap(find.text(name));
  await routes.finishRoute(tester, find.byType(XiangqiChatRoomScreen, skipOffstage: false));
  final channel = factory.channels.last;
  channel.fromServer(
    '0{"sid":"s1","upgrades":[],"pingInterval":8000,"pingTimeout":20000,"maxPayload":1000000}',
  );
  channel.fromServer('40/xiangqi,{"sid":"s1"}');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  channel.event(
    'chat.lobby.messages.success',
    chat.page([chat.message(id: 1, text: 'Room history')]),
  );
  await tester.pumpAndSettle();
  expect(find.text('Room history'), findsOneWidget);
  return channel;
}

String currentDraft(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('the public-room composer uses the same prompt as the chess chat', (tester) async {
    final factory = await chat.pumpHub(tester);
    await openLoadedRoom(tester, factory, 'English');
    final field = tester.widget<TextField>(find.byType(TextField));
    final context = tester.element(find.byType(XiangqiChatRoomScreen));
    expect(field.decoration?.hintText, context.l10n.talkInChat);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public-room messages use the chess chat list padding rather than an extra bottom gap',
    (tester) async {
      final factory = await chat.pumpHub(tester);
      await openLoadedRoom(tester, factory, 'English');
      final messages = tester.widget<ListView>(find.byType(ListView));
      expect(messages.reverse, isTrue);
      expect(messages.padding?.resolve(TextDirection.ltr).bottom, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning to the same public room restores its unsent draft without keeping the old socket',
    (tester) async {
      final factory = await chat.pumpHub(tester);
      await openLoadedRoom(tester, factory, 'English');
      await tester.enterText(find.byType(TextField), 'An unfinished English message');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openLoadedRoom(tester, factory, 'English');
      expect(
        factory.channels,
        hasLength(2),
        reason: 'Draft retention must not retain a closed-room socket.',
      );
      expect(currentDraft(tester), 'An unfinished English message');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('public-room drafts stay separate while moving between two rooms', (tester) async {
    final factory = await chat.pumpHub(tester);
    await openLoadedRoom(tester, factory, 'English');
    await tester.enterText(find.byType(TextField), 'English draft');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openLoadedRoom(tester, factory, '中文');
    expect(currentDraft(tester), isEmpty);
    await tester.enterText(find.byType(TextField), '中文草稿');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openLoadedRoom(tester, factory, 'English');
    expect(currentDraft(tester), 'English draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets('public-room drafts do not follow an account change', (tester) async {
    final factory = await chat.pumpHub(tester);
    await openLoadedRoom(tester, factory, 'English');
    await tester.enterText(find.byType(TextField), 'Account A message');
    final container = ProviderScope.containerOf(tester.element(find.byType(XiangqiChatRoomScreen)));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await container
        .read(xiangqiSessionStoreProvider)
        .write(
          const XiangqiSession(
            userId: '200002',
            name: 'account-b',
            accessToken: 'account-b-token',
            isGuest: false,
          ),
        );
    await tester.pump();
    await openLoadedRoom(tester, factory, 'English');
    expect(currentDraft(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final hidden in [false, true]) {
    testWidgets('a public-chat sender only links to the xiangqi profile when visible ($hidden)', (
      tester,
    ) async {
      final channel = await chat.pumpRoom(tester);
      channel.event(
        'chat.lobby.messages.success',
        chat.page([
          {
            ...chat.message(id: 1, text: 'From a peer', sender: 'visible-peer'),
            'sender_hidden_username': hidden,
          },
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('visible-peer'));
      await tester.pump();
      final profile = find.byType(XiangqiProfileScreen, skipOffstage: false);
      if (hidden) {
        expect(profile, findsNothing);
      } else {
        expect(profile, findsOneWidget);
        expect(tester.widget<XiangqiProfileScreen>(profile).username, 'visible-peer');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1600));
      expect(tester.takeException(), isNull);
    });
  }
}
