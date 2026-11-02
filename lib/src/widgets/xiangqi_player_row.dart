import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/player_table.dart';
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
    final showRatings = rating != null && ref.watch(ratingsVisibleProvider(false));
    final effectiveClockPosition =
        clockPosition ?? ref.watch(boardPreferencesProvider).clockPosition;

    return PlayerTable(
      clock: clock,
      clockPosition: effectiveClockPosition,
      content: Row(
        children: [
          XiangqiPieceAvatar(side: side, size: avatarSize, style: style),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerIdentityLine(
                  name: playerName,
                  compact: compact,
                  clockPosition: effectiveClockPosition,
                  afterName: [
                    if (showRatings && rating != null) ...[
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
                      Flexible(
                        child: Tooltip(
                          message: context.l10n.computer,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: context.lichessColors.fancy,
                              borderRadius: const BorderRadius.all(Radius.circular(3)),
                            ),
                            child: Text(
                              context.l10n.computer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (thinking) ...const [
                      SizedBox(width: 8),
                      Icon(Icons.hourglass_top, size: 16),
                    ],
                  ],
                ),
                ?detail,
                if (status case final text? when text.isNotEmpty)
                  Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontStyle: FontStyle.italic, color: textShade(context, 0.7)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
