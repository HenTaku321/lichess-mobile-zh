import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/game_surface_layout.dart';
import 'package:lichess_mobile/src/widgets/game_table_column.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

void main() {
  testWidgets('a sidebar relayout does not rewind an already scrolled player table', (
    tester,
  ) async {
    late StateSetter update;
    var revision = 0;
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(480, 480),
        failOnOverflow: true,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 180,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return GameTableColumn(
                    topTable: const SizedBox(
                      height: 300,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text('First table line'), Text('Last table line')],
                      ),
                    ),
                    bottomTable: const SizedBox(height: 150),
                    actions: const SizedBox(height: 56),
                    minimumMoveHeight: revision.isEven ? 0 : 1,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final topScroll = find
        .ancestor(of: find.text('Last table line'), matching: find.byType(Scrollable))
        .first;
    await tester.drag(topScroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Last table line')).dy;
    expect(
      tester.getRect(topScroll).overlaps(tester.getRect(find.text('Last table line'))),
      isTrue,
    );
    update(() => revision++);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Last table line')).dy, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  for (final moves in [false, true]) {
    testWidgets('tall landscape tables remain readable without clipping actions (moves: $moves)', (
      tester,
    ) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(480, 480),
          failOnOverflow: true,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 480,
                height: 356,
                child: GameSurfaceLayout(
                  boardBuilder: (_, _) => const SizedBox(key: Key('surface-board')),
                  boardHeightRatio: 1.1,
                  topTableBuilder: (_, _) => const SizedBox(
                    key: Key('top-table-content'),
                    height: 200,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('Top start'), Text('Top end')],
                    ),
                  ),
                  bottomTableBuilder: (_, _) => const SizedBox(
                    key: Key('bottom-table-content'),
                    height: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('Bottom start'), Text('Bottom end')],
                    ),
                  ),
                  moveListBuilder: moves ? (_) => const SizedBox(key: Key('surface-moves')) : null,
                  userActionsBar: const SizedBox(
                    key: Key('surface-actions'),
                    height: 56,
                    child: Text('Actions'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final surface = tester.getRect(find.byType(GameSurfaceLayout));
      expect(surface.size, const Size(480, 356));
      final actions = tester.getRect(find.byKey(const Key('surface-actions')));
      expect(actions.top, greaterThanOrEqualTo(surface.top));
      expect(actions.bottom, lessThanOrEqualTo(surface.bottom));
      final topScroll = find.ancestor(
        of: find.byKey(const Key('top-table-content')),
        matching: find.byType(Scrollable),
      );
      expect(topScroll, findsOneWidget);
      await tester.drag(topScroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(topScroll);
      final end = tester.getRect(find.text('Top end'));
      expect(viewport.overlaps(end), isTrue);
    });
  }

  testWidgets('fitting landscape tables retain their natural height and the full move-list space', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(1280, 720),
        failOnOverflow: true,
        home: GameSurfaceLayout(
          boardBuilder: (_, _) => const SizedBox(key: Key('surface-board')),
          boardHeightRatio: 1,
          topTableBuilder: (_, _) => const SizedBox(key: Key('top-table-content'), height: 40),
          bottomTableBuilder: (_, _) =>
              const SizedBox(key: Key('bottom-table-content'), height: 50),
          moveListBuilder: (_) => const SizedBox(key: Key('surface-moves')),
          userActionsBar: const SizedBox(key: Key('surface-actions'), height: 56),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('top-table-content'))).height, 40);
    expect(tester.getSize(find.byKey(const Key('bottom-table-content'))).height, 50);
    expect(
      tester.getSize(find.byKey(const Key('surface-moves'))).height,
      720 - 32 - 40 - 50 - 56 - 32,
    );
    expect(tester.takeException(), isNull);
  });
}
