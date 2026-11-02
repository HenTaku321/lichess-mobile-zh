import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_rules.dart' as rules;
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_friends_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_puzzle_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_saved_screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../model/xiangqi/puzzle/xiangqi_puzzle_fixture.dart' as puzzle;
import '../../network/fake_http_client_factory.dart';
import '../../network/xiangqi_http_test.dart' show FakeXiangqiAuthStorage, signedInSession;
import '../../test_provider_scope.dart';
import 'xiangqi_puzzle_screen_test.dart' as puzzles;

Future<void> settleRemote(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 1600));
  }
}

Future<void> pumpRemote(
  WidgetTester tester,
  Widget screen,
  MockClient client, {
  bool failOnOverflow = false,
  bool useRealRatingPreferences = false,
}) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: screen,
      useRealRatingPreferences: useRealRatingPreferences,
      failOnOverflow: failOnOverflow,
      overrides: {
        xiangqiAuthStorageProvider: xiangqiAuthStorageProvider.overrideWithValue(
          FakeXiangqiAuthStorage(signedInSession),
        ),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (_) => FakeHttpClientFactory(() => client),
        ),
      },
    ),
  );
  await settleRemote(tester);
}

http.Response jsonReply(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: const {'Content-Type': 'application/json'});

const folder = {
  'encrypted_id': 'FolderA',
  'name': 'A folder',
  'item_type': 2,
  'parent_encrypted_id': null,
  'is_root': true,
};

void main() {
  TestLichessBinding.ensureInitialized();

  for (final retry in [false, true]) {
    testWidgets('saved puzzle opens its exact id and returns to its list (retry: $retry)', (
      tester,
    ) async {
      const id = puzzle.xiangqiTestPuzzleId;
      final server = puzzles.PuzzleServer(searchPuzzleId: 'NoPeId');
      final requests = <http.Request>[];
      var failFetch = retry;
      await pumpRemote(
        tester,
        const XiangqiSavedScreen(),
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.startsWith('/api/puzzle/puzzles/')) {
            return jsonReply({
              'items': [
                {'puzzle_id': id, 'p_rating': 1500},
              ],
              'total_pages': 1,
            });
          }
          if (request.url.path.startsWith('/api/items/folders/')) {
            return jsonReply({'items': <Object?>[]});
          }
          if (request.url.path == '/api/puzzle/P/$id' && failFetch) {
            return jsonReply({}, 503);
          }
          return await server.answer(request);
        }),
        failOnOverflow: true,
      );
      expect(find.text(id), findsOneWidget);
      await tester.tap(find.text(id));
      if (!retry) {
        // Two real taps before the next frame must not stack two solving routes.
        await tester.tap(find.text(id));
      }
      await settleRemote(tester);
      expect(find.byType(XiangqiPuzzleScreen), findsOneWidget);
      if (retry) {
        final l10n = tester.element(find.byType(XiangqiPuzzleScreen)).l10n;
        expect(find.text(l10n.retry), findsOneWidget);
        failFetch = false;
        await tester.tap(find.text(l10n.retry));
        await settleRemote(tester);
      }
      expect(find.byType(XiangqiBoard), findsOneWidget);
      expect(
        tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).position,
        rules.play(puzzle.xiangqiTestPuzzle.position, puzzle.xiangqiTestPuzzle.blunderMove),
      );
      expect(requests.where((request) => request.url.path == '/api/puzzle/search'), isEmpty);
      expect(
        requests.where((request) => request.url.path == '/api/puzzle/P/$id'),
        hasLength(retry ? 2 : 1),
      );
      expect(
        requests.where(
          (request) => request.method == 'POST' && request.url.path.endsWith('/complete'),
        ),
        isEmpty,
      );
      Navigator.of(tester.element(find.byType(XiangqiBoard))).pop();
      await settleRemote(tester);
      expect(find.byType(XiangqiPuzzleScreen), findsNothing);
      expect(find.text(id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty folder lists settle without a phantom loading row', (tester) async {
    await pumpRemote(
      tester,
      const XiangqiSavedScreen(),
      MockClient((_) async => jsonReply({'items': <Object?>[]})),
    );
    expect(find.text('…'), findsNothing);
    expect(find.byType(RefreshIndicator), findsWidgets);
  });

  testWidgets('folder names validate in place and a failed write preserves the draft', (
    tester,
  ) async {
    var fail = true;
    final writes = <http.Request>[];
    await pumpRemote(
      tester,
      const XiangqiSavedScreen(),
      MockClient((request) async {
        if (request.method != 'GET' && request.url.path.contains('/folders')) {
          writes.add(request);
          return jsonReply({}, fail ? 503 : 201);
        }
        if (request.method != 'GET') return jsonReply({});
        return jsonReply({'items': <Object?>[]});
      }),
    );
    final l10n = tester.element(find.byType(XiangqiSavedScreen)).l10n;
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.accept));
    await tester.pump();
    expect(find.text(l10n.required), findsOneWidget);
    expect(writes, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  Opening notes  ');
    await tester.tap(find.text(l10n.accept));
    await settleRemote(tester);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '  Opening notes  ',
    );
    expect(find.text(l10n.mobileSomethingWentWrong), findsOneWidget);
    final body = jsonDecode(writes.single.body) as Map<String, dynamic>;
    expect(body['name'], 'Opening notes');
    fail = false;
    await tester.tap(find.text(l10n.accept));
    await settleRemote(tester);
    expect(writes, hasLength(2));
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('folder deletion requires explicit confirmation', (tester) async {
    final writes = <http.Request>[];
    await pumpRemote(
      tester,
      const XiangqiSavedScreen(),
      MockClient((request) async {
        if (request.method == 'DELETE') writes.add(request);
        return jsonReply({
          'items': request.url.path.contains('/folders/') ? [folder] : <Object?>[],
        });
      }),
    );
    final l10n = tester.element(find.byType(XiangqiSavedScreen)).l10n;
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text(l10n.no));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.yes));
    await settleRemote(tester);
    expect(writes, hasLength(1));
  });

  testWidgets('unfriending refreshes the active nonempty search', (tester) async {
    final reads = <Uri>[];
    var removed = false;
    await pumpRemote(
      tester,
      const XiangqiFriendsScreen(),
      MockClient((request) async {
        if (request.method == 'DELETE') {
          removed = true;
          return jsonReply({});
        }
        if (request.url.path.endsWith('friend-requests')) {
          return jsonReply({'friend_requests': <Object?>[]});
        }
        reads.add(request.url);
        return jsonReply({
          'items': removed
              ? <Object?>[]
              : [
                  {'id': '42', 'identity': 'Alice'},
                ],
          'total_pages': 1,
        });
      }),
    );
    await tester.enterText(find.byType(TextField).first, 'Alice');
    await settleRemote(tester);
    final before = reads.where((uri) => uri.queryParameters['search'] == 'Alice').length;
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await settleRemote(tester);
    expect(
      reads.where((uri) => uri.queryParameters['search'] == 'Alice').length,
      greaterThan(before),
    );
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
  });
}
