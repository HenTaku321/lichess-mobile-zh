import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart' show XiangqiSide;
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_signup_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/xiangqi_avatar.dart';
import 'package:material_ui/material_ui.dart';

/// The gaps in the form: between its blocks, and between two fields of one block.
const double _kSectionGap = 24.0;
const double _kFieldGap = 16.0;

/// The size of the general at the head of the form.
const double _kBrandPieceSize = 64.0;

/// Signs the user in to their xiangqi.com account, with an email and a password.
///
/// This is a second account, on a different service, kept beside the lichess one — it is not a
/// third way to sign in to lichess, and the line at the top of the form says so. Every request goes
/// through [xiangqiAuthControllerProvider], which owns the account; this screen only drives the
/// form around it.
class const XiangqiLoginScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const XiangqiLoginScreen());
  }

  @override
  ConsumerState<XiangqiLoginScreen> createState() => _XiangqiLoginScreenState();
}

class _XiangqiLoginScreenState() extends ConsumerState<XiangqiLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;

  /// Whether the password field is drawing dots rather than letters. It starts that way, and the
  /// eye at the end of the field is how it is opened.
  bool _obscurePassword = true;

  /// Whether the last attempt was refused over the email/password pair.
  ///
  /// Only that failure is shown under the form; every other failure (a dropped connection, a 500)
  /// goes to a snackbar, so the two are never confused for one another.
  bool _invalidCredentials = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _invalidCredentials = false;
    });

    try {
      await ref
          .read(xiangqiAuthControllerProvider.notifier)
          .signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      // The session is in storage by the time this returns, so there is nothing left to do here.
      Navigator.of(context).pop();
    } on XiangqiInvalidCredentialsException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _invalidCredentials = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Held for the screen's lifetime, for the reason the sign-up screen holds it: the controller is
    // `autoDispose`, and a sign-in is a request long enough for it to be collected in the middle of
    // one.
    ref.watch(xiangqiAuthControllerProvider);
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.mobileXiangqi)),
      body: SafeArea(
        child: ListView(
          padding: Styles.bodySectionPadding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const SizedBox(height: _kSectionGap),
            // The service's own mark: a red general, the piece every xiangqi board opens with.
            const Center(
              child: XiangqiPieceAvatar(side: XiangqiSide.red, size: _kBrandPieceSize),
            ),
            const SizedBox(height: _kSectionGap),
            Text(
              context.l10n.mobileXiangqiSignIn,
              style: TextTheme.of(context).bodyMedium?.copyWith(color: textShade(context, 0.7)),
            ),
            const SizedBox(height: _kSectionGap),
            TextField(
              controller: _emailController,
              autofocus: true,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                labelText: context.l10n.email,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: _kFieldGap),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.password,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_invalidCredentials) ...[
              const SizedBox(height: _kFieldGap),
              Text(
                context.l10n.mobileXiangqiInvalidCredentials,
                style: TextTheme.of(context).bodyMedium
                    ?.copyWith(color: ColorScheme.of(context).error),
              ),
            ],
            const SizedBox(height: _kSectionGap),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const ButtonLoadingIndicator() : Text(context.l10n.signIn),
            ),
            const SizedBox(height: _kFieldGap),
            // The other half of the same act, and the only way to an account for a reader who has
            // never had one. It is a link and not a second button: signing in is what this screen
            // is for, and making an account is where a reader who cannot sign in has to go.
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(XiangqiSignUpScreen.buildRoute()),
              child: Text(context.l10n.mobileXiangqiSignUp),
            ),
          ],
        ),
      ),
    );
  }
}
