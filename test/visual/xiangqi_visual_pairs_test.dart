import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart' hide Message;
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/conversation_controller.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/view/message/conversation_screen.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';
import 'package:lichess_mobile/src/widgets/chat_presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../binding.dart';
import '../model/auth/fake_auth_storage.dart';
import '../model/message/xiangqi_inbox_repository_test.dart' as pm;
import '../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../network/fake_http_client_factory.dart';
import '../network/fake_websocket_channel.dart';
import '../network/xiangqi_http_test.dart' as auth;
import '../test_provider_scope.dart';
import '../view/xiangqi/xiangqi_desktop_visual_test.dart' show DesktopSceneApp, loadVisualFonts;
import 'xiangqi_visual_catalogue.dart';

class _PairSocketFactory(final fx.FakeXiangqiChannelFactory xiangqi)
    implements WebSocketChannelFactory {
  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) => Uri.parse(url).path.contains('socket.io')
      ? xiangqi.create(url, headers: headers, timeout: timeout)
      : defaultFakeWebSocketChannelFactory.create(url, headers: headers, timeout: timeout);
}

class const _OpenConversation({required final bool xiangqi}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => xiangqi
                ? XiangqiConversationScreen(
                    chatId: pm.xiangqiFirstChatId,
                    peerId: pm.xiangqiFirstPeerId,
                    peer: xiangqiLightUser(pm.xiangqiFirstPeerId, 'Peer'),
                  )
                : ConversationScreen(
                    user: fakeAuthUser.user.copyWith(id: const UserId('peer'), name: 'Peer'),
                  ),
          ),
        ),
        child: const Text('Open conversation'),
      ),
    ),
  );
}

Map<String, dynamic> requestedGroups(Map<String, dynamic> specification) {
  final defaults = visualCatalogue()['defaults']! as Map<String, Object?>;
  final groups = <String, dynamic>{
    for (final entry in defaults.entries)
      entry.key: Map<String, dynamic>.from(entry.value! as Map<String, Object?>),
  };
  final configuration = specification['configuration']! as Map<String, dynamic>;
  final preferences = configuration['preferences']! as Map<String, dynamic>;
  for (final entry in preferences.entries) {
    final path = entry.key.split('.');
    final group = groups[path.first]! as Map<String, dynamic>;
    expect(group.containsKey(path.last), isTrue, reason: 'Unknown persistence field ${entry.key}');
    final value = entry.value;
    group[path.last] = value is String && group[path.last] is num ? num.parse(value) : value;
  }
  return groups;
}

Map<String, Object?> accountWire(AccountPrefState value) => {
  'prefs': {
    'zen': value.zenMode.value,
    'pieceNotation': value.pieceNotation.value,
    'ratings': value.showRatings.value,
    'premove': value.premove.value,
    'autoQueen': value.autoQueen.value,
    'autoThreefold': value.autoThreefold.value,
    'takeback': value.takeback.value,
    'moretime': value.moretime.value,
    'clockTenths': value.clockTenths.value,
    'clockSound': value.clockSound.value,
    'confirmResign': value.confirmResign.value ? 1 : 0,
    'submitMove': int.parse(value.submitMove.toFormData),
    'follow': value.follow.value,
    'challenge': value.challenge.value,
    'message': value.message.value,
  },
};

class _Capture(
  final Map<String, Object?> metadata,
  final Uint8List rgba,
  final int width,
  final int height,
);

Future<Map<String, Object?>> savePng(Directory root, String name, Uint8List bytes) async {
  await File('${root.path}/$name').writeAsBytes(bytes);
  return {'path': name, 'sha256': sha256.convert(bytes).toString()};
}

Future<_Capture> captureSide(
  WidgetTester tester,
  Map<String, dynamic> specification,
  String side,
  Directory root,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => pumpEventQueue(times: 2));
  final configuration = specification['configuration']! as Map<String, dynamic>;
  final environment = configuration['environment']! as Map<String, dynamic>;
  final dimensions = environment['size']! as List<dynamic>;
  final size = Size((dimensions[0] as num).toDouble(), (dimensions[1] as num).toDouble());
  final dpi = (environment['dpi']! as num).toDouble();
  tester.view.devicePixelRatio = dpi;
  addTearDown(tester.view.resetDevicePixelRatio);
  final groups = requestedGroups(specification);
  final account = AccountPrefState.fromJson(groups['account']! as Map<String, dynamic>);
  final localeParts = (environment['locale']! as String).split('-');
  final locale = Locale(localeParts.first, localeParts.last);
  final mode = BackgroundThemeMode.values.byName(environment['mode']! as String);
  groups['general'] = GeneralPrefs.fromJson(groups['general']! as Map<String, dynamic>)
      .copyWith(locale: locale, themeMode: mode, systemColors: false)
      .toJson();
  final sockets = fx.FakeXiangqiChannelFactory();
  final requests = <Map<String, Object?>>[];
  final messages = [
    ('Newest message', true),
    ('Previous message', true),
    ('Message from peer', false),
  ];
  final client = MockClient((request) async {
    requests.add({'kind': 'http', 'method': request.method, 'path': request.url.path});
    final Object? body = switch (request.url.path) {
      '/api/account/preferences' => accountWire(account),
      '/api/user/peer' => {'id': 'peer', 'username': 'Peer', 'blocking': false},
      '/inbox/peer' => {
        'me': {'id': fakeAuthUser.user.id.value, 'name': fakeAuthUser.user.name},
        'bot': false,
        'convo': {
          'user': {'id': 'peer', 'name': 'Peer'},
          'postable': true,
          'msgs': [
            for (var i = 0; i < messages.length; i++)
              {
                'text': messages[i].$1,
                'user': messages[i].$2 ? fakeAuthUser.user.id.value : 'peer',
                'date': DateTime(2024, 5, 6, 9, 12, 39 - i).millisecondsSinceEpoch,
              },
          ],
        },
      },
      _ => null,
    };
    return http.Response(
      jsonEncode(body),
      body == null ? 404 : 200,
      headers: const {'Content-Type': 'application/json'},
    );
  });
  final key = GlobalKey();
  final storageKeys = visualCatalogue()['storageKeys']! as Map<String, Object?>;
  await tester.pumpWidget(
    await makeTestProviderScope(
      tester,
      failOnOverflow: true,
      useRealRatingPreferences: true,
      authUser: fakeAuthUser,
      surfaceSize: size,
      defaultPreferences: {
        for (final entry in groups.entries)
          storageKeys[entry.key]! as String: jsonEncode(entry.value),
      },
      child: DesktopSceneApp(
        home: _OpenConversation(xiangqi: side == 'xiangqi'),
        locale: locale,
        mode: mode,
        textScale: (environment['textScale']! as num).toDouble(),
        captureKey: key,
      ),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
        webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
          _PairSocketFactory(sockets),
        ),
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          auth.FakeXiangqiAuthStorage(auth.signedInSession.copyWith(userId: pm.xiangqiAccountId)),
        ),
      },
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Open conversation'));
  final offsets = <fx.FakeXiangqiChannel, int>{};
  for (var round = 0; round < 12; round++) {
    for (final channel in sockets.channels) {
      var offset = offsets[channel] ?? 0;
      final frames = channel.sent.toList();
      for (; offset < frames.length; offset++) {
        final frame = frames[offset];
        if (frame is! String) continue;
        if (frame.startsWith('40/xiangqi,')) {
          channel.fromServer(fx.openFrame);
          channel.fromServer(fx.connectAckFrame);
        } else if (frame.startsWith('42/xiangqi,')) {
          final args = jsonDecode(frame.substring(frame.indexOf('['))) as List<dynamic>;
          final name = args.first as String;
          requests.add({'kind': 'socket', 'event': name});
          if (name == kXiangqiInboxChatUserEvent) {
            channel.fromServer(
              pm.xiangqiMessagesFrame([
                for (var i = 0; i < messages.length; i++)
                  pm.xiangqiMessageRow(
                    messages[i].$1,
                    senderId: messages[i].$2
                        ? int.parse(pm.xiangqiAccountId)
                        : pm.xiangqiFirstPeerId,
                    createdOn: DateTime(2024, 5, 6, 9, 12, 39 - i).toIso8601String(),
                  ),
              ]),
            );
          }
        }
      }
      offsets[channel] = offset;
    }
    await tester.pump(const Duration(milliseconds: 1600));
  }
  final proof = <Map<String, Object?>>[
    {'kind': 'tap', 'target': 'Open conversation'},
  ];
  if (specification['state'] == 'draft') {
    await tester.enterText(find.byType(TextField), 'Draft before the next input');
    await tester.pump();
    proof.add({'kind': 'enterText', 'target': 'composer'});
  }
  expect(find.byType(ChatMessageList), findsOneWidget);
  expect(find.byType(ChatComposerInput), findsOneWidget);
  final container = ProviderScope.containerOf(tester.element(find.byType(DesktopSceneApp)));
  expect(await container.read(showRatingsPrefProvider.future), account.showRatings);
  final actualBoard = container.read(boardPreferencesProvider).toJson();
  final actualPrefs = <String, Object?>{};
  final requested = configuration['preferences']! as Map<String, dynamic>;
  for (final name in requested.keys) {
    expect(
      name.startsWith('board.'),
      isTrue,
      reason: 'This driver must explicitly project every applicable preference.',
    );
    actualPrefs[name] = actualBoard[name.split('.').last];
    expect(actualPrefs[name], requested[name]);
  }
  final controllerProof = side == 'xiangqi'
      ? {
          'controller': 'XiangqiConversationController',
          'chatId': pm.xiangqiFirstChatId,
          'messages': container
              .read(
                xiangqiConversationControllerProvider((
                  chatId: pm.xiangqiFirstChatId,
                  peerId: pm.xiangqiFirstPeerId,
                  peer: xiangqiLightUser(pm.xiangqiFirstPeerId, 'Peer'),
                )),
              )
              .requireValue
              .convo
              .messages
              .length,
        }
      : {
          'controller': 'ConversationController',
          'userId': 'peer',
          'messages': container
              .read(conversationControllerProvider(const UserId('peer')))
              .requireValue
              .convo
              .messages
              .length,
        };
  expect(controllerProof['messages'], 3);
  final roles = <String, Object?>{};
  for (final (name, finder) in [
    ('appbar', find.byType(AppBar)),
    ('message-list', find.byType(ChatMessageList)),
    ('composer', find.byType(ChatComposerInput)),
    ('bubble-newest', find.byType(ChatBubbleSurface).first),
  ]) {
    final rect = tester.getRect(finder);
    roles[name] = {
      'rect': [rect.left, rect.top, rect.width, rect.height],
    };
  }
  final capture = await tester.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(
      pixelRatio: dpi,
    );
    try {
      expect(
        [image.width, image.height],
        [size.width.toInt() * dpi.toInt(), size.height.toInt() * dpi.toInt()],
      );
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final original = await savePng(root, '$side.png', png.buffer.asUint8List());
      return _Capture(
        {
          'environment': {...environment, 'dpi': tester.view.devicePixelRatio},
          'physicalSize': [image.width, image.height],
          'stage': specification['state'],
          'realRatingPreferences': true,
          'preferences': actualPrefs,
          'driverProof': proof,
          'controllerProof': controllerProof,
          'requests': requests,
          'roles': roles,
          'original': original,
        },
        rgba.buffer.asUint8List(),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  });
  expect(tester.takeException(), isNull);
  return capture!;
}

Future<Map<String, Object?>> difference(
  Directory root,
  String role,
  _Capture left,
  _Capture right,
  double dpi,
) async {
  final rects = [
    for (final capture in [left, right])
      ((capture.metadata['roles']! as Map<String, Object?>)[role]! as Map<String, Object?>)['rect']!
          as List<double>,
  ];
  final crops = [
    for (final rect in rects)
      (
        x: (rect[0] * dpi).round(),
        y: (rect[1] * dpi).round(),
        width: (rect[2] * dpi).round(),
        height: (rect[3] * dpi).round(),
      ),
  ];
  final width = crops[0].width > crops[1].width ? crops[0].width : crops[1].width;
  final height = crops[0].height > crops[1].height ? crops[0].height : crops[1].height;
  final bytes = Uint8List(width * height * 4);
  var changed = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var different = false;
      for (var component = 0; component < 3; component++) {
        final values = <int>[];
        for (var side = 0; side < 2; side++) {
          final capture = side == 0 ? left : right;
          final crop = crops[side];
          final px = crop.x + x, py = crop.y + y;
          values.add(
            x < crop.width &&
                    y < crop.height &&
                    px >= 0 &&
                    px < capture.width &&
                    py >= 0 &&
                    py < capture.height
                ? capture.rgba[(py * capture.width + px) * 4 + component]
                : 0,
          );
        }
        final delta = (values[0] - values[1]).abs();
        bytes[(y * width + x) * 4 + component] = delta;
        different |= delta != 0;
      }
      bytes[(y * width + x) * 4 + 3] = 255;
      if (different) changed++;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  try {
    final png = (await frame.image.toByteData(format: ui.ImageByteFormat.png))!;
    return {
      'image': await savePng(root, '$role-diff.png', png.buffer.asUint8List()),
      'changedPixels': changed,
      'totalPixels': width * height,
    };
  } finally {
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

void main() {
  TestLichessBinding.ensureInitialized();
  final planPath = Platform.environment['XIANGQI_PAIR_PLAN'];
  final enabled = planPath != null;
  setUpAll(() async {
    if (enabled) await loadVisualFonts();
  });
  final cases = enabled
      ? (jsonDecode(File(planPath).readAsStringSync()) as Map<String, dynamic>)['cases']!
            as List<dynamic>
      : <dynamic>[];
  if (!enabled) {
    test('visual pairs require an explicit manual Actions batch', () {}, skip: true);
    return;
  }
  for (final value in cases) {
    final specification = value as Map<String, dynamic>;
    testWidgets('pair ${specification['caseId']}', (tester) async {
      final id = specification['caseId']! as String;
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
      final root = Directory('${Platform.environment['XIANGQI_PAIR_OUTPUT']}/$id');
      await tester.runAsync(() => root.create(recursive: true));
      final report = <String, Object?>{
        for (final key in [
          'caseId',
          'sourceSha',
          'registryHash',
          'renderFingerprint',
          'configuration',
          'state',
          'allowedDifferences',
        ])
          key: specification[key],
      };
      if (specification['driver'] != 'private-conversation' ||
          !['normal', 'draft'].contains(specification['state'])) {
        report.addAll({
          'status': specification['driver'] == 'no-reference' ? 'blocked' : 'not_run',
          'reason':
              'No verified driver/reference for ${specification['role']}/${specification['state']}.',
        });
      } else {
        final left = await captureSide(tester, specification, 'lichess', root);
        final right = await captureSide(tester, specification, 'xiangqi', root);
        final configuration = specification['configuration']! as Map<String, dynamic>;
        final environment = configuration['environment']! as Map<String, dynamic>;
        final diffs = <String, Object?>{};
        await tester.runAsync(() async {
          for (final role in specification['requiredRoles']! as List<dynamic>) {
            diffs[role as String] = await difference(
              root,
              role,
              left,
              right,
              (environment['dpi']! as num).toDouble(),
            );
          }
        });
        report.addAll({
          'status': 'captured',
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'sides': {'lichess': left.metadata, 'xiangqi': right.metadata},
          'differences': diffs,
          'subjective': 'not_run',
          'nativeSound': 'not_run',
          'nativeHaptics': 'not_run',
        });
      }
      await tester.runAsync(
        () => File('${root.path}/report.json').writeAsString(jsonEncode(report)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
}
