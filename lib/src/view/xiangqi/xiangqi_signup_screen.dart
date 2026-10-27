import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart' show XiangqiSide;
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:material_ui/material_ui.dart';

const double _kSectionGap = 24.0;
const double _kFieldGap = 16.0;
const double _kBrandPieceSize = 64.0;

/// Makes a xiangqi.com account, in the three steps the site makes one in.
///
/// The steps are the server's, not this screen's: an address is given a code by email, the code is
/// handed back, and only then is there anything to attach a username and a password to. Measured on
/// 2026-10-19 — see `xiangqi-com-re/docs/auth.md` — and the account is signed in by the last call,
/// so there is nothing to sign in to afterwards.
///
/// The country is the one field the form needs that the reader has no reason to type: it is a
/// picker over the same list the profile editor offers, and it is required because the server
/// refuses the account without it.
class const XiangqiSignUpScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const XiangqiSignUpScreen());

  @override
  ConsumerState<XiangqiSignUpScreen> createState() => _XiangqiSignUpScreenState();
}

/// How far along the three steps the form is.
enum _Step() {
  /// The address, and the ask for a code.
  email,

  /// The code, and the ask for it to be checked.
  code,

  /// The account itself: a username, a password and a country.
  details,
}

class _XiangqiSignUpScreenState() extends ConsumerState<XiangqiSignUpScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscurePassword = true;

  /// What went wrong, in the reader's language, or null.
  String? _error;

  /// The country the account is filed under, as the numeric id the endpoint takes.
  int? _countryId;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _locale => xiangqiLocaleOf(Localizations.localeOf(context));

  XiangqiAuthController get _auth => ref.read(xiangqiAuthControllerProvider.notifier);

  /// Runs one step of the form, with the busy flag and the error line handled in one place.
  Future<void> _run(Future<void> Function() action, {required String onFailure}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _busy = false);
    } on XiangqiEmailTakenException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.mobileXiangqiSignUpEmailTaken;
        });
      }
    } on XiangqiInvalidCodeException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.mobileXiangqiSignUpInvalidCode;
        });
      }
    } on XiangqiInvalidUsernameException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.username;
        });
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = onFailure;
      });
      // The reason behind the sentence above, which the sentence cannot carry.
      debugPrint('xiangqi sign-up failed: $error\n$stackTrace');
    }
  }

  Future<void> _sendCode() => _run(() async {
    await _auth.sendSignUpCode(email: _email.text.trim(), locale: _locale);
    if (mounted) setState(() => _step = _Step.code);
  }, onFailure: context.l10n.mobileSomethingWentWrong);

  Future<void> _verifyCode() => _run(() async {
    await _auth.verifySignUpCode(
      email: _email.text.trim(),
      code: _code.text.trim(),
      locale: _locale,
    );
    if (mounted) setState(() => _step = _Step.details);
  }, onFailure: context.l10n.mobileSomethingWentWrong);

  Future<void> _createAccount() => _run(() async {
    final country = _countryId;
    if (country == null) return;
    await _auth.signUp(
      username: _username.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      country: '$country',
      locale: _locale,
    );
    if (!mounted) return;
    showSnackBar(context, context.l10n.mobileXiangqiSignUpDone);
    Navigator.of(context).pop();
  }, onFailure: context.l10n.mobileSomethingWentWrong);

  @override
  Widget build(BuildContext context) {
    // Watched, not merely read: the controller is `autoDispose`, and the three calls that make an
    // account are long ones. A screen that only reached for the notifier would let the controller be
    // collected mid-request — the session would be written to storage by a provider that no longer
    // exists — and this screen is about that session, so it is the right thing to hold it.
    ref.watch(xiangqiAuthControllerProvider);
    final countries = ref.watch(xiangqiCountryOptionsProvider);
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.mobileXiangqiSignUp)),
      body: SafeArea(
        child: ListView(
          padding: Styles.bodySectionPadding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const SizedBox(height: _kSectionGap),
            const Center(
              child: XiangqiPieceAvatar(side: XiangqiSide.red, size: _kBrandPieceSize),
            ),
            const SizedBox(height: _kSectionGap),
            Text(
              context.l10n.mobileXiangqiSignUp,
              style: TextTheme.of(context).bodyMedium?.copyWith(color: textShade(context, 0.7)),
            ),
            const SizedBox(height: _kSectionGap),
            TextField(
              controller: _email,
              // The address is the first step and the only field on it; once it has been given a
              // code it is read-only, because the code was sent to it and not to whatever is typed
              // over it.
              enabled: _step == _Step.email && !_busy,
              autofocus: _step == _Step.email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _step == _Step.email ? _sendCode() : null,
              decoration: InputDecoration(
                labelText: context.l10n.email,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_step == _Step.email) ...[
              const SizedBox(height: _kSectionGap),
              FilledButton(
                onPressed: _busy || _email.text.trim().isEmpty ? null : _sendCode,
                child: _busy
                    ? const ButtonLoadingIndicator()
                    : Text(context.l10n.mobileXiangqiSignUpSendCode),
              ),
            ],
            if (_step != _Step.email) ...[
              const SizedBox(height: _kFieldGap),
              Text(
                context.l10n.mobileXiangqiSignUpCodeSent(_email.text.trim()),
                style: TextTheme.of(context).bodySmall,
              ),
            ],
            if (_step == _Step.code) ...[
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _verifyCode(),
                decoration: InputDecoration(
                  labelText: context.l10n.mobileXiangqiSignUpCode,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: _kSectionGap),
              FilledButton(
                onPressed: _busy || _code.text.trim().isEmpty ? null : _verifyCode,
                child: _busy
                    ? const ButtonLoadingIndicator()
                    : Text(context.l10n.mobileXiangqiSignUpCode),
              ),
              const SizedBox(height: _kFieldGap),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: Text(context.l10n.mobileXiangqiSignUpSendCode),
              ),
            ],
            if (_step == _Step.details) ...[
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _username,
                autofocus: true,
                maxLength: 12,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: context.l10n.mobileXiangqiSignUpUsername,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.l10n.mobileXiangqiSignUpPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: _kFieldGap),
              countries.when(
                data: (options) => DropdownButtonFormField<int>(
                  initialValue: options.any((option) => option.id == _countryId)
                      ? _countryId
                      : null,
                  decoration: InputDecoration(
                    labelText: context.l10n.mobileXiangqiSignUpCountry,
                    border: const OutlineInputBorder(),
                  ),
                  menuMaxHeight: 420,
                  items: [
                    for (final option in options)
                      DropdownMenuItem<int>(value: option.id, child: Text(option.name)),
                  ],
                  onChanged: _busy ? null : (value) => setState(() => _countryId = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(
                  context.l10n.mobileSomethingWentWrong,
                  style: TextStyle(color: ColorScheme.of(context).error),
                ),
              ),
              const SizedBox(height: _kSectionGap),
              FilledButton(
                onPressed: _busy || _countryId == null ? null : _createAccount,
                child: _busy
                    ? const ButtonLoadingIndicator()
                    : Text(context.l10n.mobileXiangqiSignUp),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: _kFieldGap),
              Text(
                _error!,
                style: TextTheme.of(context).bodyMedium
                    ?.copyWith(color: ColorScheme.of(context).error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
