import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_new_game.dart';
import 'package:lichess_mobile/src/network/xiangqi_session_store.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/auth/xiangqi_login_screen.dart';
import 'package:lichess_mobile/src/view/play/common_play_widgets.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
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
///
/// ## The form is the chess lobby's panel
///
/// Setting up a game looks the same on both boards, and it is the same widgets that make it so: the
/// two rows of labelled buttons over a full-width action button are [PlaySetupButton], which the
/// chess panel is built from too. What differs is the settings, because the games differ — a
/// variant and a rating window are chess ideas, and the side and the clock are the two boards'
/// shared ones.
class const XiangqiNewGameScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiNewGameScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(xiangqiAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleText('${context.l10n.mobileXiangqi} · ${context.l10n.createAGame}'),
      ),
      body: ref.watch(xiangqiSessionReadyProvider).isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : session == null || session.isGuest
          ? _SignInPrompt(onTap: () => Navigator.of(context).push(XiangqiLoginScreen.buildRoute()))
          : _Form(key: ValueKey(ref.watch(xiangqiAccountGenerationProvider))),
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

class const _Form({super.key}) extends ConsumerStatefulWidget {
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
  bool _searching = false;
  int _searchGeneration = 0;
  XiangqiNewGameRepository? _searchRepository;
  Future<void>? _quickSubmission;
  bool _cancelling = false;
  late final XiangqiSessionStore _sessions;
  late final int _account;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(xiangqiSessionStoreProvider);
    _account = _sessions.accountGeneration;
  }

  @override
  void dispose() {
    _searchGeneration++;
    final repository = _searchRepository;
    _searchRepository = null;
    if (repository != null) unawaited(_cancelQueued(repository, submission: _quickSubmission));
    super.dispose();
  }

  Future<void> _cancelQueued(
    XiangqiNewGameRepository repository, {
    Future<void>? submission,
  }) async {
    try {
      await submission;
    } on Object {
      /* The queue may still need clearing after a lost response. */
    }
    // A shared HTTP client would otherwise cancel the newly signed-in account's queue.
    if (_sessions.accountGeneration != _account) return;
    try {
      await repository.cancelQuickChallenge();
    } on Object {
      /* Best effort; no automatic resignation. */
    }
  }

  Future<void> _cancelSearch() async {
    if (_cancelling) return;
    _searchGeneration++;
    final repository = _searchRepository;
    _searchRepository = null;
    if (mounted) {
      setState(() {
        _cancelling = true;
      });
    }
    if (repository != null) await _cancelQueued(repository, submission: _quickSubmission);
    if (mounted) {
      setState(() {
        _cancelling = false;
        _searching = false;
        _busy = false;
      });
    }
  }

  /// Whether the settings that only a game of your own has are being asked for.
  ///
  /// A quick match is one field — the time control — and everything else about the game is the
  /// server's to decide: it pairs with whoever is queued, on both sides of the board, for rating.
  /// So the second row of controls is only there for a game of your own, which is the same
  /// judgement the chess panel makes about its own second row.
  bool get _isCustom => _opponent == _Opponent.custom;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      children: [
        // The chess lobby's own panel, part for part: two rows of labelled buttons over a
        // full-width action button, and the same widget for each button. See [PlaySetupButton],
        // which is what the two panels share.
        Row(
          children: [
            Expanded(
              child: PlaySetupButton(
                label: context.l10n.opponent,
                value: _opponentLabel(context),
                icon: _isCustom ? Icons.tune : Icons.bolt,
                onPressed: _busy
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
                          onSelectedItemChanged: (opponent) {
                            if (mounted) setState(() => _opponent = opponent);
                          },
                        );
                      },
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: PlaySetupButton(
                label: context.l10n.clock,
                value: _timeControlLabel(context, _timeControl),
                icon: Icons.timer_outlined,
                valueStyle: const TextStyle(letterSpacing: 2.0),
                onPressed: _busy
                    ? null
                    : () {
                        showChoicePicker<XiangqiTimeControl>(
                          context,
                          title: Text(context.l10n.clock),
                          choices: XiangqiTimeControl.values,
                          selectedItem: _timeControl,
                          labelBuilder: (control) => Text(_timeControlLabel(context, control)),
                          onSelectedItemChanged: (control) {
                            if (mounted) setState(() => _timeControl = control);
                          },
                        );
                      },
              ),
            ),
          ],
        ),
        if (_isCustom) ...[
          const SizedBox(height: 6.0),
          Row(
            children: [
              Expanded(
                child: PlaySetupButton(
                  label: context.l10n.side,
                  value: _sideLabel(context, _side),
                  onPressed: _busy
                      ? null
                      : () {
                          showChoicePicker<XiangqiSideChoice>(
                            context,
                            title: Text(context.l10n.side),
                            choices: XiangqiSideChoice.values,
                            selectedItem: _side,
                            labelBuilder: (side) => Text(_sideLabel(context, side)),
                            onSelectedItemChanged: (side) {
                              if (mounted) setState(() => _side = side);
                            },
                          );
                        },
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: PlaySetupButton(
                  label: context.l10n.gameMode,
                  value: _rated ? context.l10n.rated : context.l10n.casual,
                  onPressed: _busy
                      ? null
                      : () {
                          showChoicePicker<bool>(
                            context,
                            title: Text(context.l10n.gameMode),
                            choices: const [false, true],
                            selectedItem: _rated,
                            labelBuilder: (rated) =>
                                Text(rated ? context.l10n.rated : context.l10n.casual),
                            onSelectedItemChanged: (rated) {
                              if (mounted) setState(() => _rated = rated);
                            },
                          );
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          // The one setting that is a yes or a no rather than a choice between things, drawn the
          // way this app draws every other one of those.
          SwitchSettingTile(
            title: Text(context.l10n.mobileXiangqiPrivateGame),
            value: _private,
            onChanged: _busy ? null : (value) => setState(() => _private = value),
          ),
        ],
        const SizedBox(height: 16.0),
        FilledButton.icon(
          icon: Icon(_isCustom ? Icons.add : Icons.bolt),
          onPressed: _busy ? null : _play,
          label: Text(
            _isCustom ? context.l10n.createAGame : context.l10n.mobileXiangqiQuickGame,
            style: Styles.bold,
          ),
        ),
        if (_searching) ...[
          const Center(child: CircularProgressIndicator.adaptive()),
          Text(context.l10n.mobileXiangqiSearching, textAlign: TextAlign.center),
          TextButton(
            onPressed: _cancelling ? null : _cancelSearch,
            child: Text(context.l10n.cancel),
          ),
        ],
      ],
    );
  }

  String _opponentLabel(BuildContext context) =>
      _isCustom ? context.l10n.mobileXiangqiCreateGame : context.l10n.mobileXiangqiQuickGame;

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
    if (_busy) return;
    final generation = ++_searchGeneration;
    setState(() => _busy = true);
    try {
      final repository = ref.read(xiangqiNewGameRepositoryProvider);
      if (_opponent == _Opponent.quick) {
        _searchRepository = repository;
        setState(() => _searching = true);
        _quickSubmission = repository.quickChallenge(_timeControl);
        await _quickSubmission;
        if (!mounted || generation != _searchGeneration) {
          return;
        }
        final gameId = await _waitForOpponent(repository, generation);
        if (!mounted ||
            generation != _searchGeneration ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        _searchRepository = null;
        setState(() => _searching = false);
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
      if (!mounted ||
          generation != _searchGeneration ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      await Navigator.of(context).push(XiangqiOnlineGameScreen.buildRoute(gameId));
    } on Object catch (error, stackTrace) {
      if (generation != _searchGeneration) return;
      final repository = _searchRepository;
      _searchRepository = null;
      if (repository != null) await _cancelQueued(repository);
      if (!mounted) return;
      showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      // The stack is not shown to the reader; it is here so that a failure that only happens on one
      // machine is not a failure with nothing behind it.
      debugPrint('$error\n$stackTrace');
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _busy = false;
          _searching = false;
        });
      }
    }
  }

  /// Waits for the quick match to name a game, or gives up.
  ///
  /// **Giving up cancels the match**, and that is not tidiness: a match left in the pool would pair
  /// the account with somebody after the screen that asked for it had gone, and the game would be
  /// sitting there waiting for a player who never comes back. The cancel is best-effort — a failed
  /// cancel is not worth an error over a screen that is leaving anyway.
  Future<String?> _waitForOpponent(XiangqiNewGameRepository repository, int generation) async {
    for (var round = 0; round < xiangqiQuickMatchRounds; round++) {
      await Future<void>.delayed(kXiangqiQuickMatchPollInterval);
      if (!mounted || generation != _searchGeneration) return null;
      final status = await repository.challengeStatus();
      if (!mounted || generation != _searchGeneration) return null;
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
