import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

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
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.mobileXiangqi)),
      body: SafeArea(
        child: ListView(
          padding: Styles.bodySectionPadding,
          children: [
            Text(context.l10n.mobileXiangqiSignIn),
            const SizedBox(height: 24.0),
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
            const SizedBox(height: 16.0),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.password,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_invalidCredentials) ...[
              const SizedBox(height: 16.0),
              Text(
                context.l10n.mobileXiangqiInvalidCredentials,
                style: TextTheme.of(context).bodyMedium
                    ?.copyWith(color: ColorScheme.of(context).error),
              ),
            ],
            const SizedBox(height: 24.0),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const ButtonLoadingIndicator() : Text(context.l10n.signIn),
            ),
          ],
        ),
      ),
    );
  }
}
