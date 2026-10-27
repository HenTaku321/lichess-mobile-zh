import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_user_repository.dart';
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:material_ui/material_ui.dart';

/// The edit form for the fields xiangqi.com lets an account change.
///
/// The website's own form sends the account's country, biography and username, plus a password
/// when the username changes. The same fields are sent here; email is shown as the account's fixed
/// identity rather than made editable, because changing it is a separate verification flow.
class const XiangqiProfileEditScreen({required final String username, super.key})
    extends ConsumerStatefulWidget {
  static Route<String?> buildRoute(String username) =>
      buildScreenRoute<String?>(screen: XiangqiProfileEditScreen(username: username));

  @override
  ConsumerState<XiangqiProfileEditScreen> createState() => _XiangqiProfileEditScreenState();
}

class _XiangqiProfileEditScreenState() extends ConsumerState<XiangqiProfileEditScreen> {
  String? _ownerId;
  int? _ownerGeneration;

  @override
  Widget build(BuildContext context) {
    final username = widget.username;
    final accountGeneration = ref.watch(xiangqiAccountGenerationProvider);
    final session = ref.watch(xiangqiAuthControllerProvider);
    // A rename publishes its name before storage finishes. Bind ownership to the id so that the
    // form remains mounted until its successful update returns and closes the route. Bind only
    // once: a later session, even with the same username, cannot take over this route.
    if (_ownerId == null && session != null && !session.isGuest && session.name == username) {
      _ownerId = session.userId;
      _ownerGeneration = accountGeneration;
    }
    if (session == null ||
        session.isGuest ||
        session.userId != _ownerId ||
        accountGeneration != _ownerGeneration) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.editProfile)),
        body: Center(child: Text(context.l10n.mobileXiangqiSignIn)),
      );
    }
    final profile = ref.watch(xiangqiEditableProfileProvider(username));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.editProfile)),
      body: profile.when(
        data: (profile) => _EditForm(key: ValueKey(accountGeneration), profile: profile),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: Styles.bodySectionPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.mobileSomethingWentWrong, textAlign: TextAlign.center),
                const SizedBox(height: 16.0),
                FilledButton(
                  onPressed: () => ref.invalidate(xiangqiEditableProfileProvider(username)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _EditForm({required final XiangqiEditableProfile profile, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState() extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _bio;
  final _password = TextEditingController();
  late int? _countryId;
  bool _saving = false;
  String? _error;

  bool get _usernameChanged => _username.text.trim() != widget.profile.username;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.profile.username);
    _bio = TextEditingController(text: widget.profile.bio);
    _countryId = widget.profile.countryId;
  }

  @override
  void dispose() {
    _username.dispose();
    _bio.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final generation = ref.read(xiangqiAccountGenerationProvider);
    try {
      final updated = await updateXiangqiProfile(
        ref.read(xiangqiClientProvider),
        username: widget.profile.username,
        newUsername: _username.text.trim(),
        bio: _bio.text,
        countryId: _countryId,
        password: _password.text,
      );
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      await ref.read(xiangqiAuthControllerProvider.notifier).updateUsername(updated.username);
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      ref.invalidate(xiangqiEditableProfileProvider(widget.profile.username));
      ref.invalidate(xiangqiEditableProfileProvider(updated.username));
      ref.invalidate(xiangqiUserProvider(widget.profile.username));
      ref.invalidate(xiangqiUserProvider(updated.username));
      if (mounted) Navigator.of(context).pop(updated.username);
    } on Object catch (_) {
      if (!mounted || generation != ref.read(xiangqiAccountGenerationProvider)) return;
      setState(() {
        _saving = false;
        _error = context.l10n.mobileSomethingWentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(xiangqiCountryOptionsProvider);
    return Form(
      key: _formKey,
      child: ListView(
        padding: Styles.bodySectionPadding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          TextFormField(
            controller: _username,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: context.l10n.username,
              border: const OutlineInputBorder(),
            ),
            maxLength: 12,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final username = value?.trim() ?? '';
              if (username.isEmpty) return context.l10n.username;
              if (username.length > 12) return context.l10n.username;
              return null;
            },
          ),
          const SizedBox(height: 12.0),
          countries.when(
            data: (options) => DropdownButtonFormField<int>(
              initialValue: options.any((option) => option.id == _countryId) ? _countryId : null,
              decoration: InputDecoration(
                labelText: context.l10n.countryRegion,
                border: const OutlineInputBorder(),
              ),
              menuMaxHeight: 420,
              items: [
                for (final option in options)
                  DropdownMenuItem<int>(value: option.id, child: Text(option.name)),
              ],
              onChanged: _saving ? null : (value) => setState(() => _countryId = value),
              validator: (value) => value == null ? context.l10n.countryRegion : null,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(
              context.l10n.mobileSomethingWentWrong,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _bio,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: context.l10n.biography,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
            minLines: 5,
            maxLines: 8,
            maxLength: 1022,
          ),
          if (_usernameChanged) ...[
            const SizedBox(height: 12.0),
            TextFormField(
              controller: _password,
              enabled: !_saving,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: context.l10n.password,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').isEmpty ? context.l10n.password : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12.0),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24.0),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18.0,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2.0),
                  )
                : Text(context.l10n.save),
          ),
        ],
      ),
    );
  }
}
