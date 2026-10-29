// Deterministic Linux screenshots, opt-in on Actions with real Roboto and pinned CJK fonts.
// No production account, native engine, live HTTP or real socket is involved.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessground/chessground.dart' show Chessboard;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart' show Variant;
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/message/xiangqi_inbox_repository.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/chat/xiangqi_chat.dart';
import 'package:lichess_mobile/src/model/xiangqi/lesson/xiangqi_lesson.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_analysis_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart' show webSocketChannelFactoryProvider;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_socket.dart';
import 'package:lichess_mobile/src/theme.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/message/xiangqi_conversation_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_analysis_settings_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_board_editor_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_database_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lesson_player_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lessons_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_over_the_board_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_edit_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_puzzle_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_review_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_saved_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_signup_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_watch_screen.dart';
import 'package:lichess_mobile/src/widgets/window_title_bar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/message/xiangqi_inbox_repository_test.dart' as pm;
import '../../model/xiangqi/database/xiangqi_master_game_test.dart' as database;
import '../../model/xiangqi/lesson/xiangqi_lesson_test.dart' as lessons;
import '../../model/xiangqi/online/xiangqi_online_game_fixture.dart' as fx;
import '../../model/xiangqi/tournament/xiangqi_tournament_test.dart' as tournaments;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' as auth;
import '../../test_provider_scope.dart';
import 'xiangqi_analysis_screen_test.dart' as analysis;
import 'xiangqi_chat_screen_test.dart' as chat;
import 'xiangqi_leaderboard_screen_test.dart' as leaders;
import 'xiangqi_notifications_screen_test.dart' as notifications;
import 'xiangqi_puzzle_screen_test.dart' as puzzles;
import 'xiangqi_review_screen_test.dart' as review;
import 'xiangqi_watch_screen_test.dart' as watch;

const reviewId = 'RvWxYz9012';
const longName = '很长的棋友姓名 Long player name for desktop overflow checks';

class const DesktopSceneApp({
  required final Widget home,
  required final Locale locale,
  required final BackgroundThemeMode mode,
  required final double textScale,
  required final GlobalKey captureKey,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      MaterialLocalizationsEo.delegate,
      CupertinoLocalizationsEo.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: makeAppTheme(
      context,
      themeMode: mode,
      backgroundColor: null,
      backgroundImage: null,
      systemColors: false,
      boardTheme: ref.watch(boardPreferencesProvider).boardTheme,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(key: captureKey, child: buildAppWindow(context, child)),
    ),
    home: home,
  );
}

Future<void> loadVisualFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  for (final (family, path) in [
    ('Roboto', '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
    ('Roboto', '$sdk/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf'),
    ('Roboto', '$sdk/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf'),
    ('MaterialIcons', '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    (
      'Noto Sans CJK SC',
      '${Platform.environment['XIANGQI_VISUAL_FONT_DIR']}/NotoSansCJKsc-Regular.otf',
    ),
    (
      'Noto Serif CJK SC',
      '${Platform.environment['XIANGQI_VISUAL_FONT_DIR']}/NotoSerifCJKsc-Regular.otf',
    ),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  await (FontLoader(
    'packages/cupertino_icons/CupertinoIcons',
  )..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
  await (FontLoader(
    'LichessIcons',
  )..addFont(rootBundle.load('assets/fonts/LichessIcons.ttf'))).load();
}

http.Response visualJson(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'Content-Type': 'application/json'},
);

http.Response visualHttp(http.Request request, {required bool empty, required bool error}) {
  if (error) return visualJson({'error': 'fixture unavailable'}, 503);
  final path = request.url.path;
  if (path == '/api/v2/games/active') return visualJson(empty ? <Object?>[] : [watch.entry()]);
  if (path == '/api/lessons/levels') {
    return visualJson({
      'topics': empty ? <Object?>[] : [lessons.topic(title: longName)],
    });
  }
  if (path.startsWith('/api/lessons/topic/')) {
    return visualJson({
      ...lessons.topic(),
      'lessons': empty ? <Object?>[] : [lessons.lesson(title: longName)],
    });
  }
  if (path.contains('/chapters')) {
    return visualJson({
      'chapters': empty ? <Object?>[] : [lessons.chapter()],
    });
  }
  if (path.contains('/master-games/players') && path.endsWith('/stats')) {
    return visualJson({'wins': 12, 'losses': 3, 'draws': 2, 'country': 'CN'});
  }
  if (path.contains('/master-games/players') && path.endsWith('/games')) {
    return visualJson(
      database.page(empty ? <Map<String, Object?>>[] : [database.row()], nextPage: 2),
    );
  }
  if (path.contains('/master-games/players')) {
    return visualJson(
      database.page(
        empty ? <Map<String, Object?>>[] : [database.player(name: longName)],
        nextPage: 2,
      ),
    );
  }
  if (path.contains('/master-games/games/')) return visualJson(database.game());
  if (path == '/api/tournament/list') {
    return visualJson({
      'active': empty ? <Object?>[] : [tournaments.tournament(name: longName)],
      'previous': <Object?>[],
    });
  }
  if (path.contains('/tournament/') && path.endsWith('/leaders')) {
    return visualJson({
      'participants': empty ? <Object?>[] : [tournaments.participant(name: longName)],
      'total_pages': 1,
    });
  }
  if (path.contains('/participants/')) {
    return visualJson(empty ? <Object?>[] : [tournaments.participant(name: longName)]);
  }
  if (path.startsWith('/api/tournament/')) {
    return visualJson(tournaments.tournament(name: longName));
  }
  if (path == '/api/leaders/v2/list') {
    return visualJson(
      leaders.board(
        data: empty ? <Map<String, Object?>>[] : [leaders.row(name: longName, rating: 2400)],
        totalPlayers: empty ? 0 : 1,
      ),
    );
  }
  if (path == '/api/chat_rooms/') {
    return visualJson(
      empty
          ? <Object?>[]
          : [
              {'name': '中文', 'description': longName, 'code': 'CN'},
            ],
    );
  }
  if (path == '/api/friends/friend-requests') return visualJson({'friend_requests': <Object?>[]});
  if (path.startsWith('/api/friends/')) {
    return visualJson({
      'items': empty
          ? <Object?>[]
          : [
              {'id': '42', 'identity': longName},
            ],
      'total_pages': 1,
    });
  }
  if (path.contains('/items/folders/')) {
    return visualJson({
      'items': empty
          ? <Object?>[]
          : [
              {'encrypted_id': 'FolderA', 'name': longName, 'item_type': 2, 'is_root': true},
            ],
    });
  }
  if (path.contains('/items/')) return visualJson({'items': <Object?>[]});
  if (path.startsWith('/api/puzzle/puzzles/')) {
    return visualJson({
      'items': empty
          ? <Object?>[]
          : [
              {
                'puzzle_id': 'FixturePuzzle',
                'theme': 1,
                'p_rating': 1500,
                'created_on': '2026-10-15',
              },
            ],
      'total_pages': 1,
    });
  }
  if (path.startsWith('/api/game-note/game-notes/')) {
    return visualJson({'items': <Object?>[], 'total_pages': 0});
  }
  if (path == '/api/users/countries') {
    return visualJson([
      {'id': 1, 'code': 'CN', 'name': 'China', 'value': 1},
    ]);
  }
  if (path.startsWith('/api/users/account/')) {
    return visualJson({
      'id': pm.xiangqiAccountId,
      'username': 'Tester',
      'identity': 'Tester',
      'bio': longName,
      'email': 'fixture@example.invalid',
      'country': {'id': 1, 'code': 'CN', 'name': 'China'},
      'bullet_rating': 900,
      'rapid_rating': 1200,
      'daily_rating': 1000,
      'puzzle_rating': 600,
      'member_since': 'Thu, 15 Oct 2026 14:05:19 GMT',
      'last_online': '1792142453',
    });
  }
  if (path.contains('/multiplayer_stats/')) {
    return visualJson({
      'wins': 12,
      'losses': 3,
      'draws': 2,
      'win_rate': 70,
      'total_games': 17,
      'highest_rating': 1800,
    });
  }
  if (path.contains('/puzzle_stats/')) {
    return visualJson({'attempted': 20, 'success_rate': 70, 'highest_rating': 1800});
  }
  if (path.contains('/users/games/')) return visualJson({'items': <Object?>[], 'total_pages': 0});
  return visualJson({}, 404);
}

/// Answer each emitted fixture frame once, preserving the real client/controller request order.
void answerVisualSockets(
  fx.FakeXiangqiChannelFactory factory,
  Map<fx.FakeXiangqiChannel, int> offsets,
  String scene,
) {
  for (final channel in factory.channels) {
    var offset = offsets[channel] ?? 0;
    final frames = channel.sent.toList();
    for (; offset < frames.length; offset++) {
      final frame = frames[offset];
      if (frame is! String) continue;
      if (frame.startsWith('40/xiangqi,')) {
        channel.fromServer(fx.openFrame);
        channel.fromServer(fx.connectAckFrame);
        continue;
      }
      final bracket = frame.indexOf('[');
      if (!frame.startsWith('42/xiangqi,') || bracket < 0) continue;
      final args = jsonDecode(frame.substring(bracket)) as List<dynamic>;
      final event = args.first;
      if (event == 'g_v2.get' || event == 'game.archived.get') {
        channel.fromServer(
          fx.xiangqiEventFrame('game.get.success', {
            ...fx.xiangqiSnapshotPayload(
              plies: scene == 'review' ? 4 : 2,
              ended: scene == 'review',
            ),
            'id': scene == 'review' ? reviewId : fx.xiangqiTestGameId,
            'archive': scene == 'review',
            'initial_fen': kXiangqiInitialFen,
          }),
        );
      } else if (event == 'g_v2.review') {
        channel.fromServer(review.reviewFrame());
      } else if (event == 'get.notifications') {
        channel.fromServer(
          notifications.notificationsFrame([
            notifications.notification(title: longName, message: '通知示例 Example notification'),
          ]),
        );
      } else if (event == 'chat_v2.messages') {
        channel.fromServer(
          fx.xiangqiEventFrame(
            'chat.lobby.messages.success',
            chat.page([chat.message(id: 1, text: longName)]),
          ),
        );
      } else if (event == kXiangqiInboxChatUserEvent) {
        channel.fromServer(
          pm.xiangqiMessagesFrame([
            pm.xiangqiMessageRow('私信示例 Example message', senderId: pm.xiangqiFirstPeerId),
          ]),
        );
      }
    }
    offsets[channel] = offset;
  }
}

void main() {
  TestLichessBinding.ensureInitialized();
  final enabled = Platform.environment['XIANGQI_DESKTOP_VISUALS'] == '1';
  setUpAll(() async {
    if (enabled) await loadVisualFonts();
  });
  setUp(() {
    clearSavedXiangqiAnalysis();
    // Real page focus callbacks still run; only the native Pigeon acknowledgement is simulated.
    const channel = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      channel,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    addTearDown(() => messenger.setMockMessageHandler(channel, null));
  });
  tearDown(clearSavedXiangqiAnalysis);

  final chapters = xiangqiChaptersFromJson({
    'chapters': [lessons.chapter()],
  });
  final scenes = <(String, Widget)>[
    ('analysis', const XiangqiAnalysisScreen()),
    ('analysis-ready', const XiangqiAnalysisScreen()),
    ('analysis-menu', const XiangqiAnalysisScreen()),
    ('analysis-settings', const XiangqiAnalysisSettingsScreen()),
    (
      'lichess-analysis',
      const AnalysisScreen(options: AnalysisOptions.standalone(variant: Variant.standard)),
    ),
    ('online', const XiangqiOnlineGameScreen(gameId: fx.xiangqiTestGameId)),
    ('review', const XiangqiReviewScreen(gameId: reviewId)),
    ('editor', const XiangqiBoardEditorScreen()),
    (
      'computer',
      const XiangqiGameScreen(
        initialSide: XiangqiSide.red,
        initialDifficulty: XiangqiDifficulty.level1,
        initialTimeIncrement: TimeIncrement.infinite(),
      ),
    ),
    ('otb-setup', const XiangqiOverTheBoardScreen()),
    ('database', const XiangqiDatabaseScreen()),
    ('database-game', const XiangqiMasterGameScreen(slug: 'a-vs-b')),
    ('master-player', const XiangqiMasterPlayerScreen(playerId: 1, playerName: longName)),
    ('lessons', const XiangqiLessonsScreen()),
    ('topic', const XiangqiTopicScreen(topicId: 'AbCdEf')),
    ('chapters', const XiangqiLessonScreen(lessonId: 'GhIjKl', lessonTitle: longName)),
    (
      'lesson-player',
      XiangqiLessonPlayerScreen(
        lessonId: 'GhIjKl',
        lessonTitle: longName,
        chapters: chapters,
        initialIndex: 0,
      ),
    ),
    ('puzzle', const XiangqiPuzzleScreen()),
    ('tournaments', const XiangqiTournamentsScreen()),
    ('tournament', const XiangqiTournamentScreen(id: 'AbCdEf', name: longName)),
    ('leaderboard', const XiangqiLeaderboardScreen()),
    ('profile', const XiangqiProfileScreen(username: 'Tester')),
    ('profile-edit', const XiangqiProfileEditScreen(username: 'Tester')),
    ('signup', const XiangqiSignUpScreen()),
    ('friends', const XiangqiFriendsScreen()),
    ('saved', const XiangqiSavedScreen()),
    ('notifications', const XiangqiNotificationsScreen()),
    ('rooms', const XiangqiChatScreen()),
    (
      'room',
      const XiangqiChatRoomScreen(roomKey: (kind: XiangqiChatKind.lobby, room: '中文'), title: '中文'),
    ),
    (
      'pm',
      XiangqiConversationScreen(
        chatId: pm.xiangqiFirstChatId,
        peerId: pm.xiangqiFirstPeerId,
        peer: xiangqiLightUser('${pm.xiangqiFirstPeerId}', pm.xiangqiFirstPeerName),
      ),
    ),
    ('watch', const XiangqiWatchScreen()),
    ('watch-empty', const XiangqiWatchScreen()),
    ('watch-error', const XiangqiWatchScreen()),
    ('database-error', const XiangqiDatabaseScreen()),
  ];
  for (final (scene, screen) in scenes) {
    for (final size in const [Size(480, 480), Size(1280, 720), Size(1920, 1080)]) {
      for (final mode in const [BackgroundThemeMode.light, BackgroundThemeMode.dark]) {
        for (final locale in const [Locale('en', 'GB'), Locale('zh', 'CN')]) {
          for (final scale in const [1.0, 2.0]) {
            final name =
                '$scene-${size.width.toInt()}x${size.height.toInt()}-${mode.name}-${locale.toLanguageTag()}-${scale.toInt()}x';
            testWidgets(
              name,
              (tester) async {
                final fake = analysis.fakeXiangqiEngine();
                final factory = fx.FakeXiangqiChannelFactory();
                final socket = XiangqiSocketClient(
                  channelFactory: factory,
                  getToken: () async => fx.xiangqiTestToken(pm.xiangqiAccountId),
                );
                addTearDown(socket.dispose);
                final puzzle = puzzles.PuzzleServer();
                final httpRequests = <String>[];
                final client = MockClient((request) async {
                  httpRequests.add('${request.method} ${request.url.path}');
                  return (request.url.path.startsWith('/api/puzzle') &&
                              !request.url.path.startsWith('/api/puzzle/puzzles/')) ||
                          request.url.path.startsWith('/api/quota')
                      ? await puzzle.answer(request)
                      : visualHttp(
                          request,
                          empty: scene.endsWith('-empty'),
                          error: scene.endsWith('-error'),
                        );
                });
                final key = GlobalKey();
                await tester.pumpWidget(
                  await makeTestProviderScope(
                    tester,
                    surfaceSize: size,
                    child: DesktopSceneApp(
                      home: screen,
                      locale: locale,
                      mode: mode,
                      textScale: scale,
                      captureKey: key,
                    ),
                    defaultPreferences: {
                      ...analysis.evaluationPreferences(isEnabled: false),
                      PrefCategory.general.storageKey: jsonEncode(
                        GeneralPrefs.defaults
                            .copyWith(locale: locale, themeMode: mode, systemColors: false)
                            .toJson(),
                      ),
                    },
                    overrides: {
                      xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((_) => fake.engine),
                      xiangqiSocketProvider: xiangqiSocketProvider.overrideWith((ref) {
                        ref.onDispose(socket.dispose);
                        return socket;
                      }),
                      webSocketChannelFactoryProvider: webSocketChannelFactoryProvider
                          .overrideWithValue(factory),
                      xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
                        auth.FakeXiangqiAuthStorage(
                          auth.signedInSession.copyWith(userId: pm.xiangqiAccountId),
                        ),
                      ),
                      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
                        (_) => FakeHttpClientFactory(() => client),
                      ),
                    },
                  ),
                );
                final offsets = <fx.FakeXiangqiChannel, int>{};
                for (var i = 0; i < 12; i++) {
                  answerVisualSockets(factory, offsets, scene);
                  await tester.pump(const Duration(milliseconds: 1600));
                }
                if (scene.startsWith('analysis') && scene != 'analysis-settings') {
                  final container = ProviderScope.containerOf(
                    tester.element(find.byType(XiangqiAnalysisScreen)),
                  );
                  final controller = container.read(xiangqiAnalysisControllerProvider.notifier);
                  controller.play(XiangqiMove.parseIccs('h2e2')!);
                  controller.play(XiangqiMove.parseIccs('h9g7')!);
                  await tester.pump();
                  if (scene == 'analysis-ready') {
                    await container.read(engineEvaluationPreferencesProvider.notifier).toggle();
                    await analysis.startSearch(tester, fake.transport);
                    await analysis.answer(
                      tester,
                      fake.transport,
                      'info depth 14 score cp 37 pv h0g2 b9c7 e3e4',
                    );
                  } else if (scene == 'analysis-menu') {
                    await tester.tap(find.byIcon(Icons.menu));
                    await tester.pump(const Duration(milliseconds: 350));
                  }
                }
                final exception = tester.takeException();
                final container = ProviderScope.containerOf(
                  tester.element(find.byType(DesktopSceneApp)),
                );
                final puzzleSearch = scene == 'puzzle'
                    ? container.read(xiangqiPuzzleSearchProvider(xiangqiDefaultPuzzleSearch))
                    : null;
                final texts = tester
                    .widgetList<Text>(find.byType(Text))
                    .map((w) => w.data)
                    .whereType<String>()
                    .toList();
                final boards = [
                  for (final element in find.byType(XiangqiBoard).evaluate())
                    tester.getRect(find.byElementPredicate((e) => identical(e, element))),
                ];
                await tester.runAsync(() async {
                  final image =
                      await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
                          .toImage();
                  final data = await image.toByteData(format: ui.ImageByteFormat.png);
                  final dest = Directory(Platform.environment['XIANGQI_SCREENSHOT_DIR']!);
                  await dest.create(recursive: true);
                  await File('${dest.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
                  await File('${dest.path}/$name.json').writeAsString(
                    jsonEncode({
                      'scene': scene,
                      'width': image.width,
                      'height': image.height,
                      'locale': locale.toLanguageTag(),
                      'scale': scale,
                      'theme': mode.name,
                      'source': Platform.environment['GITHUB_SHA'],
                      'requests': httpRequests,
                      'texts': texts,
                      'puzzleSearch': puzzleSearch?.toString(),
                      'boards': [
                        for (final rect in boards)
                          {
                            'x': rect.left,
                            'y': rect.top,
                            'width': rect.width,
                            'height': rect.height,
                          },
                      ],
                      'exception': exception?.toString(),
                    }),
                  );
                  image.dispose();
                });
                expect(exception, isNull);
                expect(find.byType(ErrorWidget), findsNothing);
                if (!scene.endsWith('-error')) {
                  expect(
                    find.text(key.currentContext!.l10n.mobileSomethingWentWrong),
                    findsNothing,
                  );
                }
                if (const {
                  'analysis',
                  'analysis-ready',
                  'analysis-menu',
                  'online',
                  'review',
                  'editor',
                  'computer',
                  'otb-setup',
                  'database-game',
                  'lesson-player',
                  'puzzle',
                }.contains(scene)) {
                  expect(
                    boards,
                    hasLength(1),
                    reason:
                        'a loaded $scene must render its real board; requests=$httpRequests puzzleSearch=$puzzleSearch',
                  );
                }
                if (scene == 'lichess-analysis') expect(find.byType(Chessboard), findsOneWidget);
                for (final board in boards) {
                  expect(
                    board.width,
                    greaterThan(100),
                    reason: 'the board must remain usable, not collapse to a sliver',
                  );
                  expect(board.left, greaterThanOrEqualTo(-1));
                  expect(board.right, lessThanOrEqualTo(size.width + 1));
                  expect(board.bottom, lessThanOrEqualTo(size.height + 1));
                }
              },
              variant: TargetPlatformVariant.only(TargetPlatform.linux),
              skip: !enabled,
            );
          }
        }
      }
    }
  }
}
