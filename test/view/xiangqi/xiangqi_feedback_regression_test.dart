import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import 'xiangqi_chat_screen_test.dart' as chat;
import 'xiangqi_new_game_screen_test.dart' as games;

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('cancelling quick match clears the queue and prevents navigation', (tester) async {
    final sent = await games.pumpNewGame(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Quick game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(sent.map((r) => r.$1), contains('/api/games/cancel-quick-challenge'));
    expect(find.byType(XiangqiOnlineGameScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a chat history error stops the loading indicator', (tester) async {
    final channel = await chat.pumpRoom(tester);
    channel.event('chat.error', {'message': 'unavailable'});
    await tester.pump();
    await tester.pump();
    expect(find.byType(XiangqiChatRoomScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('unanswered history offers retry instead of spinning forever', (tester) async {
    await chat.pumpRoom(tester);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
