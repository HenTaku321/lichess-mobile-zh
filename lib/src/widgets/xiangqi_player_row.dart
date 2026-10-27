import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_board.dart';
import 'package:material_ui/material_ui.dart';

/// One player row beside a xiangqi board.
///
/// This is the xiangqi counterpart of the chess screens' `GamePlayer`: same avatar, name, rating,
/// engine badge, thinking hourglass, status line and clock placement. The two games keep their own
/// seat names and pieces; what is shared is the composition and the visual hierarchy.
class const XiangqiPlayerRow({
  required final XiangqiSide side,
  required final XiangqiBoardStyle style,
  final String? name,
  final String? rating,
  final bool isBot = false,
  final bool thinking = false,
  final bool isMe = false,
  final bool isToMove = true,
  final String? status,
  final Widget? detail,
  final Widget? clock,
  final ClockPosition? clockPosition,
  final double avatarSize = 40,

  /// Analysis headers are 26px high and have only a single compact identity line.
  final bool compact = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerName = name ?? side.label(context.l10n);
    final fontSize = compact
        ? 13.0
        : isShortVerticalScreen(context)
        ? 15.0
        : 16.0;
    final effectiveClockPosition =
        clockPosition ?? ref.watch(boardPreferencesProvider).clockPosition;

    return Row(
      children: [
        if (clock != null && effectiveClockPosition == .left) Flexible(flex: 3, child: clock!),
        if (clock != null && effectiveClockPosition == .left) const SizedBox(width: 8),
        XiangqiPieceAvatar(side: side, size: avatarSize, style: style),
        const SizedBox(width: 8),
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Tooltip(
                      message: playerName,
                      child: Text(
                        playerName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (rating != null) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        rating!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 11 : 14,
                          color: textShade(context, 0.7),
                        ),
                      ),
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.person, size: 16, color: textShade(context, 0.5)),
                  ],
                  if (isBot) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.lichessColors.fancy,
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                      child: Text(
                        context.l10n.computer,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                  if (thinking) ...const [SizedBox(width: 8), Icon(Icons.hourglass_top, size: 16)],
                ],
              ),
              ?detail,
              if (status case final status? when status.isNotEmpty)
                Text(
                  status,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.7)),
                ),
            ],
          ),
        ),
        if (clock != null && effectiveClockPosition == .right) ...[
          const SizedBox(width: 8),
          Flexible(flex: 3, child: clock!),
        ],
      ],
    );
  }
}
