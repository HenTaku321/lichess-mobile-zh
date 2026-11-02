import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/widgets/anchored_list_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final reverse in [false, true]) {
    testWidgets('variable-height insertion preserves a visible row (reverse: $reverse)', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var rows = List.generate(
        30,
        (index) => (id: 'row-$index', height: index.isEven ? 48.0 : 75.0),
      );
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AnchoredListView(
                  controller: controller,
                  reverse: reverse,
                  itemCount: rows.length,
                  itemKey: (index) => rows[index].id,
                  itemBuilder: (context, index) => SizedBox(
                    height: rows[index].height,
                    child: Center(child: Text(rows[index].id)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      controller.jumpTo(480);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(AnchoredListView));
      final anchor = find.text('row-10');
      expect(anchor, findsOneWidget);
      expect(viewport.overlaps(tester.getRect(anchor)), isTrue);
      final before = tester.getTopLeft(anchor).dy;
      update(() {
        rows = [(id: 'new-a', height: 89.0), (id: 'new-b', height: 113.0), ...rows];
      });
      await tester.pumpAndSettle();
      expect(anchor, findsOneWidget);
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a viewport at the newest edge follows inserted rows rather than anchoring old content',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var rows = ['old'];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AnchoredListView(
                controller: controller,
                itemCount: rows.length,
                itemKey: (index) => rows[index],
                itemBuilder: (context, index) => SizedBox(height: 64, child: Text(rows[index])),
              );
            },
          ),
        ),
      );
      update(() => rows = ['new', ...rows]);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(find.text('new'), findsOneWidget);
    },
  );
}
