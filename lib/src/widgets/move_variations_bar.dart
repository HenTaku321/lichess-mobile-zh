import 'package:material_ui/material_ui.dart';

const kMoveVariationCellWidth = 55;

class const MoveVariationChoice<T>({
  required final T value,
  required final String label,
  required final bool mainline,
});

/// Shared branch selector; the adapter supplies only domain identity and notation.
class const MoveVariationsBar<T>({
  required final List<MoveVariationChoice<T>> choices,
  required final ValueChanged<T> onSelect,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (choices.length <= 1) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / kMoveVariationCellWidth).floor().clamp(1, 8);
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < choices.length; i += columns)
              Row(
                children: [
                  for (final choice in choices.skip(i).take(columns))
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: theme.dividerColor),
                            bottom: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                        child: Material(
                          color: choice.mainline
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.secondaryContainer,
                          child: InkWell(
                            key: ValueKey(choice.value),
                            onTap: () => onSelect(choice.value),
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: kMinInteractiveDimension,
                              ),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  choice.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: choice.mainline
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
