import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/game_family.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/offline_computer/computer_game_slots.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/offline_computer/computer_game_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_ui/material_ui.dart';

class const ComputerGamesSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPikafish = ref.watch(engineAvailabilityProvider.select((engines) => engines.pikafish));
    return ListSection(
      header: Text(context.l10n.playAgainstComputer),
      materialFilledCard: true,
      hasLeading: true,
      children: [
        for (final family in GameFamily.values.where((family) => !family.isXiangqi || hasPikafish))
          ListTile(
            key: ValueKey('home-computer-${family.name}'),
            leading: Icon(family.isXiangqi ? Icons.grid_on : Icons.memory),
            title: Text(family.isXiangqi ? context.l10n.mobileXiangqi : context.l10n.mobileChess),
            subtitle:
                ref.watch(computerGameSlotProvider(family)).value == ComputerSlotStatus.resumable
                ? Text(context.l10n.resume)
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(
                context,
                rootNavigator: true,
              ).push(ComputerGameScreen.buildRoute(family: family));
              if (context.mounted) ref.invalidate(computerGameSlotProvider);
            },
          ),
      ],
    );
  }
}
