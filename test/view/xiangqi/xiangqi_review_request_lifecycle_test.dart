import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_refresh.dart';

import '../../binding.dart';
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../test_helpers.dart';
import 'xiangqi_review_screen_test.dart' as review;

Future<fx.FakeXiangqiChannel> _requestSnapshot(WidgetTester tester, {bool autoAck = true}) async {
  final factory = await review.pumpReview(tester);
  final channel = factory.channel;
  channel.autoAck = autoAck;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);
  await pumpUntil(tester, () => channel.hasSentEvent('g_v2.get'));
  return channel;
}

Future<void> _receive(WidgetTester tester, fx.FakeXiangqiChannel channel, String frame) async {
  channel.fromServer(frame);
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> _snapshot(WidgetTester tester, fx.FakeXiangqiChannel channel) async {
  await _receive(
    tester,
    channel,
    fx.xiangqiEventFrame('game.get.success', review.snapshotPayload()),
  );
}

String _getAck(fx.FakeXiangqiChannel channel, Object ack) {
  final raw = channel.sent.whereType<String>().firstWhere((raw) => raw.contains('"g_v2.get"'));
  final id = RegExp(r'^42/xiangqi,(\d+)').firstMatch(raw)!.group(1)!;
  return '43/xiangqi,$id${jsonEncode([ack])}';
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('a review requests analysis immediately after a snapshot even without its ack', (
    tester,
  ) async {
    final channel = await _requestSnapshot(tester, autoAck: false);
    channel.autoAck = true;
    await _snapshot(tester, channel);
    expect(channel.hasSentEvent('g_v2.review'), isTrue);
    await _receive(tester, channel, review.reviewFrame());
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(channel.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a complete review is displayed and closes its socket without an analysis ack', (
    tester,
  ) async {
    final channel = await _requestSnapshot(tester);
    channel.autoAck = false;
    await _snapshot(tester, channel);
    expect(channel.hasSentEvent('g_v2.review'), isTrue);
    await _receive(tester, channel, review.reviewFrame());
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(channel.closed, isTrue);
    await tester.pump(const Duration(seconds: 46));
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a redirect ack arriving after its snapshot cannot start another snapshot walk', (
    tester,
  ) async {
    final channel = await _requestSnapshot(tester, autoAck: false);
    channel.autoAck = true;
    await _snapshot(tester, channel);
    await _receive(tester, channel, _getAck(channel, fx.xiangqiRedirectAck));
    expect(channel.hasSentEvent('game.archived.get'), isFalse);
    expect(channel.hasSentEvent('g_v2.review'), isTrue);
    await _receive(tester, channel, review.reviewFrame());
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final duringAnalysis in [false, true]) {
    testWidgets('a review server error exposes retry immediately, analysis: $duringAnalysis', (
      tester,
    ) async {
      final channel = await _requestSnapshot(tester);
      if (duringAnalysis) await _snapshot(tester, channel);
      await _receive(
        tester,
        channel,
        fx.xiangqiEventFrame('game.error', {
          'data': {'game_id': 'RvWxYz9012', 'message': 'Game unavailable'},
        }),
      );
      expect(find.text('The review could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(channel.closed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final duringAnalysis in [false, true]) {
    testWidgets(
      'refreshing a pending review retires the old conversation, analysis: $duringAnalysis',
      (tester) async {
        final factory = await review.pumpReview(tester);
        final oldChannel = factory.channel;
        oldChannel.fromServer(fx.openFrame);
        oldChannel.fromServer(fx.connectAckFrame);
        await pumpUntil(tester, () => oldChannel.hasSentEvent('g_v2.get'));
        if (duringAnalysis) await _snapshot(tester, oldChannel);

        await tester.tap(find.byType(DesktopRefreshButton));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        expect(oldChannel.closed, isTrue);
        expect(factory.channels, hasLength(2));
        final current = factory.channel;
        current.fromServer(fx.openFrame);
        current.fromServer(fx.connectAckFrame);
        await pumpUntil(tester, () => current.hasSentEvent('g_v2.get'));
        await _snapshot(tester, current);

        // The abandoned frame has the right game and ply count, but belongs to the old request.
        await _receive(tester, oldChannel, review.reviewFrame());
        expect(find.byType(XiangqiBoard), findsNothing);
        expect(current.closed, isFalse);
        await _receive(tester, current, review.reviewFrame());
        expect(find.byType(XiangqiBoard), findsOneWidget);
        expect(current.closed, isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets('an error carrying another game id cannot reject the active review', (tester) async {
    final channel = await _requestSnapshot(tester);
    await _receive(
      tester,
      channel,
      fx.xiangqiEventFrame('game.error', {
        'data': {'game_id': 'another-game', 'message': 'Game unavailable'},
      }),
    );
    expect(find.text('The review could not be loaded.'), findsNothing);
    await _snapshot(tester, channel);
    await _receive(tester, channel, review.reviewFrame());
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
