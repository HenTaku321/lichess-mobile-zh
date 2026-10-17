import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/widgets/source_preview_block.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  testWidgets('a source block switches its preview for the expanded body', (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SourcePreviewBlock(
              title: const Text('Source'),
              preview: const Text('preview'),
              expanded: const Text('expanded'),
              expandedState: expanded,
              onToggle: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );

    expect(find.text('preview'), findsOneWidget);
    expect(find.text('expanded'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('preview'), findsNothing);
    expect(find.text('expanded'), findsOneWidget);
    await tester.tap(find.text('Less'));
    await tester.pump();
    expect(find.text('preview'), findsOneWidget);
  });
}
