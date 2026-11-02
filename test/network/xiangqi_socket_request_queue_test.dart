import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket_request_queue.dart';

import 'xiangqi_socket_test.dart' as fx;

typedef QueueHarness = ({
  XiangqiSocketRequestQueue queue,
  XiangqiSocketClient root,
  fx.FakeXiangqiChannelFactory factory,
});

QueueHarness makeQueue({
  Duration timeout = const Duration(milliseconds: 300),
  Future<String?> Function()? getToken,
}) {
  final factory = fx.FakeXiangqiChannelFactory();
  final root = XiangqiSocketClient(
    channelFactory: factory,
    getToken: getToken ?? () async => 'queue-token',
  );
  final queue = XiangqiSocketRequestQueue(socket: root, timeout: timeout);
  addTearDown(root.dispose);
  addTearDown(queue.dispose);
  return (queue: queue, root: root, factory: factory);
}

Future<fx.FakeXiangqiChannel> handshake(QueueHarness harness) async {
  await pumpEventQueue();
  final channel = harness.factory.channels.last;
  channel.fromServer(fx.openFrame);
  channel.fromServer(fx.connectAckFrame);
  await pumpEventQueue();
  return channel;
}

Future<String> read(QueueHarness harness, {Object? key, bool ack = false}) => harness.queue.read(
  event: 'request',
  data: const {},
  response: 'reply',
  decode: (data) => data! as String,
  key: key,
  ack: ack,
);

String reply(String text) => '42/xiangqi,["reply",${jsonEncode(text)}]';

void main() {
  test('coalesces a key without creating a second anonymous read', () async {
    final harness = makeQueue();
    final first = read(harness, key: 'page-one');
    final second = read(harness, key: 'page-one');
    final channel = await handshake(harness);
    expect(identical(first, second), isTrue);
    expect(
      channel.sent.whereType<String>().where((frame) => frame.contains('request')),
      hasLength(1),
    );
    channel.fromServer(reply('one answer'));
    expect(await first, 'one answer');
    expect(await second, 'one answer');
  });

  test('a reply before emission cannot satisfy the queued read', () async {
    final harness = makeQueue();
    final answer = read(harness);
    String? observed;
    answer.then<void>((value) {
      observed = value;
    }).ignore();
    await pumpEventQueue();
    final channel = harness.factory.channels.last;
    channel.fromServer(fx.openFrame);
    channel.fromServer(reply('unsolicited'));
    await pumpEventQueue();
    expect(observed, isNull);
    channel.fromServer(fx.connectAckFrame);
    await pumpEventQueue();
    channel.fromServer(reply('requested'));
    expect(await answer, 'requested');
  });

  test('a stalled preparation expires without blocking the next sender', () async {
    final harness = makeQueue();
    final blocked = Completer<void>();
    final first = harness.queue.read<String>(
      event: 'request',
      data: const {},
      response: 'reply',
      prepare: () => blocked.future,
      decode: (data) => data! as String,
    );
    await expectLater(first, throwsA(isA<TimeoutException>()));
    final next = read(harness);
    next.ignore();
    final channel = await handshake(harness);
    channel.fromServer(reply('next sender'));
    expect(await next, 'next sender');
    blocked.complete();
    await pumpEventQueue();
    expect(
      channel.sent.whereType<String>().where((frame) => frame.contains('request')),
      hasLength(1),
    );
  });

  test('late token acquisition cannot emit a request that already expired', () async {
    final token = Completer<String?>();
    final harness = makeQueue(getToken: () => token.future);
    final answer = read(harness);
    await expectLater(answer, throwsA(isA<TimeoutException>()));
    token.complete('late-token');
    await pumpEventQueue();
    expect(harness.factory.channels, isEmpty);
    expect(harness.root.isDisposed, isFalse);
  });

  test('the business reply is decisive even when the server never ACKs the emit', () async {
    final harness = makeQueue();
    final answer = read(harness, ack: true);
    final channel = await handshake(harness);
    channel.fromServer(reply('before ACK'));
    expect(await answer, 'before ACK');
  });

  test('a parse failure retires the stream before another read', () async {
    final harness = makeQueue();
    final bad = harness.queue.read<String>(
      event: 'request',
      data: const {},
      response: 'reply',
      decode: (_) => throw const FormatException('Bad page'),
    );
    final failed = expectLater(bad, throwsFormatException);
    final old = await handshake(harness);
    old.fromServer(reply('malformed'));
    await failed;
    expect(old.closed, isTrue);
    final next = read(harness);
    next.ignore();
    final fresh = await handshake(harness);
    expect(harness.factory.channels, hasLength(2));
    old.fromServer(reply('late malformed request'));
    fresh.fromServer(reply('fresh request'));
    expect(await next, 'fresh request');
  });

  test('an identity change cannot apply a previously emitted reply', () async {
    final harness = makeQueue();
    var current = true;
    final answer = harness.queue.read<String>(
      event: 'request',
      data: const {},
      response: 'reply',
      decode: (data) => data! as String,
      isCurrent: () => current,
    );
    final failed = expectLater(answer, throwsA(isA<XiangqiSocketException>()));
    final channel = await handshake(harness);
    current = false;
    channel.fromServer(reply('old account'));
    await failed;
    expect(channel.closed, isTrue);
  });

  test('failed active reads do not announce idle reconnects and cause retry loops', () async {
    final harness = makeQueue();
    var resets = 0;
    final subscription = harness.queue.resets.listen((_) => resets++);
    addTearDown(subscription.cancel);
    final first = read(harness);
    final failed = expectLater(first, throwsA(isA<TimeoutException>()));
    await handshake(harness);
    await failed;
    await pumpEventQueue();
    expect(resets, 0);
  });

  test('an idle disconnect retires its transport and announces one resynchronisation', () async {
    final harness = makeQueue();
    var resets = 0;
    final subscription = harness.queue.resets.listen((_) => resets++);
    addTearDown(subscription.cancel);
    final first = read(harness);
    final old = await handshake(harness);
    old.fromServer(reply('loaded'));
    await first;
    await pumpEventQueue();
    old.closeFromServer();
    await pumpEventQueue();
    expect(resets, 1);
    expect(old.closed, isTrue);
    final second = read(harness);
    final fresh = await handshake(harness);
    fresh.fromServer(reply('resynchronised'));
    expect(await second, 'resynchronised');
  });

  test('dispose completes queued reads and does not close the root client', () async {
    final harness = makeQueue();
    final first = read(harness, key: 'first');
    final second = read(harness, key: 'second');
    final firstError = expectLater(first, throwsA(isA<XiangqiSocketException>()));
    final secondError = expectLater(second, throwsA(isA<XiangqiSocketException>()));
    final channel = await handshake(harness);
    harness.queue.dispose();
    await Future.wait([firstError, secondError]);
    expect(channel.closed, isTrue);
    expect(harness.root.isDisposed, isFalse);
  });
}
