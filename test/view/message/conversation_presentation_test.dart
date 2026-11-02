import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/message/conversation_screen.dart';
import 'package:lichess_mobile/src/widgets/chat_presentation.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

Future<void> pumpChessConversation(
  WidgetTester tester, {
  bool blocked = false,
  bool postable = true,
}) async {
  final client = MockClient((request) async {
    if (request.url.path == '/inbox/peer') {
      return http.Response(
        jsonEncode({
          'me': {'name': 'Me', 'id': 'me'},
          'bot': false,
          'convo': {
            'user': {'name': 'Peer', 'id': 'peer'},
            'msgs': [
              {'text': 'Newest message', 'user': 'me', 'date': 1621533015388},
              {
                'text': 'Previous message https://example.invalid/path',
                'user': 'me',
                'date': 1621533014388,
              },
              {'text': 'Message from peer', 'user': 'peer', 'date': 1621533013388},
            ],
            'postable': postable,
          },
        }),
        200,
      );
    }
    if (request.url.path == '/api/user/peer') {
      return http.Response(
        jsonEncode({'id': 'peer', 'username': 'Peer', 'blocking': blocked}),
        200,
      );
    }
    return http.Response('', 404);
  });
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: const ConversationScreen(
        user: LightUser(id: UserId('peer'), name: 'Peer'),
      ),
      authUser: const AuthUser(
        token: 'test-token',
        user: LightUser(id: UserId('me'), name: 'Me'),
      ),
      surfaceSize: const Size(480, 480),
      failOnOverflow: true,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets(
    'the real chess conversation keeps grouped bubbles, timestamp reservation and composer geometry',
    (tester) async {
      await pumpChessConversation(tester);
      final surfaces = tester
          .widgetList<ChatBubbleSurface>(find.byType(ChatBubbleSurface))
          .toList();
      expect(surfaces, hasLength(3));
      expect(
        surfaces.every((surface) => surface.appearance == ChatAppearance.conversation),
        isTrue,
      );
      expect(
        surfaces
            .take(2)
            .map((surface) => (surface.isMine, surface.groupLength, surface.groupIndex)),
        [(true, 2, 0), (true, 2, 1)],
      );
      expect(surfaces.last.isMine, isFalse);
      expect(find.byType(ChatDaySeparator), findsOneWidget);
      for (final link in tester.widgetList<RichLinkText>(find.byType(RichLinkText))) {
        expect(link.trailing, isA<WidgetSpan>());
      }
      final input = tester.widget<ChatComposerInput>(find.byType(ChatComposerInput));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(input.appearance, ChatAppearance.conversation);
      expect(field.readOnly, isFalse);
      expect(
        field.decoration?.contentPadding,
        const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      );
      expect(field.maxLines, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final blocked in [false, true]) {
    testWidgets('shared chess PM input retains its protocol read-only state ($blocked)', (
      tester,
    ) async {
      await pumpChessConversation(tester, blocked: blocked, postable: false);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(
        field.decoration?.hintText,
        blocked ? 'This conversation is blocked.' : "Peer doesn't accept new messages.",
      );
      expect(find.byType(ChatBubbleSurface), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
