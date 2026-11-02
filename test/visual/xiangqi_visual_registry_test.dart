import 'dart:convert';
import 'dart:io';

import 'package:chessground/chessground.dart' show PieceSet;
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';

import 'xiangqi_visual_catalogue.dart';

void main() {
  test(
    'the visual registry names all 49 real entry roles and existing source boundaries',
    () async {
      final registry = jsonDecode(
        await File('test/visual/xiangqi_pair_registry.json').readAsString(),
      ) as Map<String, dynamic>;
      final roles = registry['roles']! as List<dynamic>;
      expect(roles, hasLength(49));
      final ids = <String>{};
      for (final value in roles) {
        final role = value as Map<String, dynamic>;
        expect(ids.add(role['id']! as String), isTrue);
        final sources = role['sources']! as Map<String, dynamic>;
        for (final source in sources.values) {
          if (source == null) {
            expect(role['driver'], 'no-reference');
            expect(role['referenceGap'], isNotEmpty);
          } else {
            expect(
              File(source as String).existsSync(),
              isTrue,
              reason: 'Missing source for ${role['id']}: $source',
            );
          }
        }
      }
      final catalogue = visualCatalogue();
      final axes = catalogue['axes']! as Map<String, Object?>;
      expect(axes['boardTheme'], hasLength(BoardTheme.values.length));
      expect(axes['pieceSet'], hasLength(PieceSet.values.length));
      final destination = Platform.environment['XIANGQI_VISUAL_CATALOGUE'];
      if (destination != null) {
        final file = File(destination);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(catalogue));
      }
    },
  );
}
