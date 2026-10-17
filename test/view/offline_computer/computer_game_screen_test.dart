import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_availability.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/offline_computer/offline_computer_game_storage.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_game_storage.dart';
import 'package:lichess_mobile/src/view/offline_computer/computer_game_screen.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_game_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../binding.dart';
import '../../model/engine/fake_transport.dart';
import '../../test_provider_scope.dart';

class MockOfflineComputerGameStorage() extends Mock implements OfflineComputerGameStorage;

final class const _NoSavedXiangqiGame() implements XiangqiGameStorage {
  @override
  Future<SavedXiangqiGame?> fetchGame() async => null;

  @override
  Future<void> save(SavedXiangqiGame game) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('switching to Pikafish replaces the board inside the same route', (tester) async {
    final gameStorage = MockOfflineComputerGameStorage();
    when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
    final transport = FakeTransport(
      spec: const PikafishSpec(nnuePath: '/test/pikafish.nnue'),
      startupLines: kPikafishHandshake,
    );
    final engine = Engine(transport);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const ComputerGameScreen(),
        overrides: {
          engineAvailabilityProvider: engineAvailabilityProvider.overrideWithValue(
            EngineAvailability.phone,
          ),
          xiangqiEngineProvider: xiangqiEngineProvider.overrideWith((Ref ref) => engine),
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (ref) => gameStorage,
          ),
          xiangqiGameStorageProvider: xiangqiGameStorageProvider.overrideWith(
            (ref) => const _NoSavedXiangqiGame(),
          ),
        },
        defaultPreferences: {
          PrefCategory.engineEvaluation.storageKey: jsonEncode(
            EngineEvaluationPrefState.defaults.copyWith(isEnabled: false).toJson(),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Opponent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pikafish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Play'));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(XiangqiGameScreen), findsOneWidget);
    expect(find.byType(OfflineComputerGameScreen), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(navigator.canPop(), isFalse, reason: 'the switch must not add a route');
  });
}
