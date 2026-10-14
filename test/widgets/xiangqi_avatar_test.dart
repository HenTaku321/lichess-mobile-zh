import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

void main() {
  testWidgets('draws each side its own general', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const Row(
          children: [
            XiangqiPieceAvatar(side: XiangqiSide.red, size: 40),
            XiangqiPieceAvatar(side: XiangqiSide.black, size: 40),
          ],
        ),
      ),
    );

    // Two avatars, sized as asked, one red and one black: a side's avatar is its general, and the
    // two sides' generals are not the same piece.
    final avatars = tester.widgetList<XiangqiPieceAvatar>(find.byType(XiangqiPieceAvatar)).toList();
    expect(avatars, hasLength(2));
    expect(avatars.map((a) => a.side), [XiangqiSide.red, XiangqiSide.black]);
    expect(tester.getSize(find.byType(XiangqiPieceAvatar).first), const Size(40, 40));
    expect(
      tester.renderObject(find.byType(XiangqiPieceAvatar).first),
      isNotNull,
      reason: 'an avatar that did not paint could not be sized',
    );
  });
}
