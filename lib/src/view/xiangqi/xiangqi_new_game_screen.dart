import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_new_game.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

/// How often a quick match asks whether an opponent has been found.
///
/// The site's own client polls; this is the same question asked at a rate a person can watch
/// without the screen flickering. The server pairs within a couple of seconds when it is going to
/// pair at all, so a dozen rounds is generous — see [xiangqiQuickMatchRounds].
const Duration kXiangqiQuickMatchPollInterval = Duration(milliseconds: 1500);

/// How many times a quick match asks before it gives up.
const int xiangqiQuickMatchRounds = 12;

/// Starts a game on xiangqi.com: a quick match, or a game of your own.
///
/// ## Why this is a screen and not a sheet
///
/// The chess "play against the computer" setup is a sheet because the game it starts replaces the
/// board underneath. This one does not: the game it starts is on xiangqi.com, in a screen of its
/// own, and a sheet would have to be dismissed before that screen could be pushed. A screen is also
/// what the lobby's own two cards are — see `xiangqi-com-re/docs/game.md` for the two calls behind
/// them.
///
/// ## What it offers, and what it does not
///
/// Two ways in, both measured on 2026-10-19:
///
/// * **A quick match** asks to be queued with one field, a time control, and then polls until the
///   server names a game. The site pairs with a bot when no person is queued, which is what makes
///   this cheap; the app does not care which it got.
/// * **A game of your own** is created with the whole of its settings in one call, and its id is
///   the game. Nobody is in the other seat yet, so the screen behind it is the game screen with an
///   empty seat and an invite button.
///
/// A daily game, an email invitation and a rating window are all things the endpoint takes and this
/// screen does not offer — see [XiangqiCustomGameRequest], which keeps the fields so that they are
/// a screen's work and not a protocol's.
class const XiangqiNewGameScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiNewGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(xiangqiAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.createAGame}'),
      ),
      body: session == null || session.isGuest
          ? _SignInPrompt(onTap: () => Navigator.of(context).push(XiangqiLoginScreen.buildRoute()))
          : const _Form(),
    );
  }
}

class const _SignInPrompt({required final VoidCallback onTap}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Styles.bodySectionPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.mobileXiangqiSignIn, textAlign: TextAlign.center),
            const SizedBox(height: 16.0),
            FilledButton(onPressed: onTap, child: Text(context.l10n.signIn)),
          ],
        ),
      ),
    );
  }
}

/// Which of the two ways in this screen is set to take.
enum _Opponent() {
  quick,
  custom,
}

class const _Form() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState() extends ConsumerState<_Form> {
  _Opponent _opponent = _Opponent.quick;
  XiangqiTimeControl _timeControl = XiangqiTimeControl.defaultControl;
  XiangqiSideChoice _side = XiangqiSideChoice.either;
  bool _rated = false;
  bool _private = true;

  /// Whether a request is on its way. One flag for both ways in: the two cannot be asked at once
  /// from one screen, and a second button that could be pressed while the first is out would be a
  /// second game.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      children: [
        ListSection(
          materialFilledCard: true,
          children: [
            SettingsListTile(
              icon: const Icon(Icons.bolt),
              settingsLabel: Text(context.l10n.opponent),
              settingsValue: switch (_opponent) {
                _Opponent.quick => context.l10n.mobileXiangqiQuickGame,
                _Opponent.custom => context.l10n.mobileXiangqiCreateGame,
              },
              explanation: switch (_opponent) {
                _Opponent.quick => context.l10n.mobileXiangqiQuickGameSubtitle,
                _Opponent.custom => context.l10n.mobileXiangqiCreateGameSubtitle,
              },
              onTap: _busy
                  ? null
                  : () {
                      showChoicePicker<_Opponent>(
                        context,
                        title: Text(context.l10n.opponent),
                        choices: _Opponent.values,
                        selectedItem: _opponent,
                        labelBuilder: (opponent) => Text(switch (opponent) {
                          _Opponent.quick => context.l10n.mobileXiangqiQuickGame,
                          _Opponent.custom => context.l10n.mobileXiangqiCreateGame,
                        }),
                        onSelectedItemChanged: (opponent) => setState(() => _opponent = opponent),
                      );
                    },
            ),
            SettingsListTile(
              settingsLabel: Text(context.l10n.clock),
              settingsValue: _timeControlLabel(context, _timeControl),
              onTap: _busy
                  ? null
                  : () {
                      showChoicePicker<XiangqiTimeControl>(
                        context,
                        title: Text(context.l10n.clock),
                        choices: XiangqiTimeControl.values,
                        selectedItem: _timeControl,
                        labelBuilder: (control) => Text(_timeControlLabel(context, control)),
                        onSelectedItemChanged: (control) => setState(() => _timeControl = control),
                      );
                    },
            ),
            SettingsListTile(
              settingsLabel: Text(context.l10n.side),
              settingsValue: _sideLabel(context, _side),
              onTap: _busy
                  ? null
                  : () {
                      showChoicePicker<XiangqiSideChoice>(
                        context,
                        title: Text(context.l10n.side),
                        choices: XiangqiSideChoice.values,
                        selectedItem: _side,
                        labelBuilder: (side) => Text(_sideLabel(context, side)),
                        onSelectedItemChanged: (side) => setState(() => _side = side),
                      );
                    },
            ),
          ],
        ),
        if (_opponent == _Opponent.custom)
          ListSection(
            materialFilledCard: true,
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.rated),
                value: _rated,
                onChanged: _busy ? null : (value) => setState(() => _rated = value),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.mobileXiangqiPrivateGame),
                value: _private,
                onChanged: _busy ? null : (value) => setState(() => _private = value),
              ),
            ],
          ),
        Padding(
          padding: Styles.horizontalBodyPadding,
          child: FilledButton(
            onPressed: _busy ? null : _play,
            child: Text(
              _opponent == _Opponent.quick
                  ? context.l10n.mobileXiangqiQuickGame
                  : context.l10n.createAGame,
              style: Styles.bold,
            ),
          ),
        ),
      ],
    );
  }

  String _timeControlLabel(BuildContext context, XiangqiTimeControl control) {
    final increment = control.increment;
    return increment == null
        ? '${control.total.inMinutes} + 0'
        : '${control.total.inMinutes} + ${increment.inSeconds}';
  }

  String _sideLabel(BuildContext context, XiangqiSideChoice side) => switch (side) {
    .red => context.l10n.mobileXiangqiSideRed,
    .either => context.l10n.randomColor,
    .black => context.l10n.mobileXiangqiSideBlack,
  };

  Future<void> _play() async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(xiangqiNewGameRepositoryProvider);
      if (_opponent == _Opponent.quick) {
        await repository.quickChallenge(_timeControl);
        if (!mounted) return;
        final gameId = await _waitForOpponent(repository);
        if (!mounted) return;
        if (gameId == null) {
          showSnackBar(context, context.l10n.mobileXiangqiNoGames);
          return;
        }
        await Navigator.of(context).push(XiangqiOnlineGameScreen.buildRoute(gameId));
        return;
      }

      final gameId = await repository.createCustom(
        XiangqiCustomGameRequest(
          timeControl: _timeControl,
          side: _side,
          rated: _rated,
          private: _private,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push(XiangqiOnlineGameScreen.buildRoute(gameId));
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      // The stack is not shown to the reader; it is here so that a failure that only happens on one
      // machine is not a failure with nothing behind it.
      debugPrint('$error\n$stackTrace');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Waits for the quick match to name a game, or gives up.
  ///
  /// **Giving up cancels the match**, and that is not tidiness: a match left in the pool would pair
  /// the account with somebody after the screen that asked for it had gone, and the game would be
  /// sitting there waiting for a player who never comes back. The cancel is best-effort — a failed
  /// cancel is not worth an error over a screen that is leaving anyway.
  Future<String?> _waitForOpponent(XiangqiNewGameRepository repository) async {
    for (var round = 0; round < xiangqiQuickMatchRounds; round++) {
      await Future<void>.delayed(kXiangqiQuickMatchPollInterval);
      if (!mounted) return null;
      final status = await repository.challengeStatus();
      if (status case XiangqiChallengeMatched(:final gameId)) return gameId;
    }
    try {
      await repository.cancelQuickChallenge();
    } on Object {
      // Best effort; see above.
    }
    return null;
  }
}
