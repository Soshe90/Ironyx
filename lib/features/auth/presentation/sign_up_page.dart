import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
import 'auth_failure_messages.dart';
import 'widgets/auth_form_scaffold.dart';

/// Creates an account, then sends the user on to Personal Details.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthFormScaffold(
      title: l10n.authCreateAccountTitle,
      intro: l10n.authCreateAccountIntro,
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: l10n.authCreateAccountTitle,
      onSubmit: _submit,
      fields: <Widget>[
        TextFormField(
          controller: _email,
          decoration: InputDecoration(labelText: l10n.authFieldEmail),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          validator: (String? value) => AuthValidators.email(value, l10n),
        ),
        TextFormField(
          controller: _password,
          decoration: InputDecoration(
            labelText: l10n.authFieldPassword,
            helperText: l10n.authPasswordHelper(
              AuthValidators.minPasswordLength,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: _obscure
                  ? l10n.authShowPassword
                  : l10n.authHidePassword,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          autofillHints: const <String>[AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          validator: (String? value) => AuthValidators.password(value, l10n),
        ),
        TextFormField(
          controller: _confirm,
          decoration: InputDecoration(labelText: l10n.authFieldConfirmPassword),
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          validator: (String? value) =>
              AuthValidators.confirmPassword(value, _password.text, l10n),
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: TextButton(
        onPressed: _busy
            ? null
            : () => context.pushReplacementNamed(Routes.signInName),
        child: Text(l10n.authHaveAccountSignIn),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final SignUpOutcome outcome =
          await ref.read(authControllerProvider.notifier).signUp(
                email: _email.text,
                password: _password.text,
              );
      if (!mounted) return;

      // Two genuinely different outcomes. Treating them alike would either
      // strand a user on a screen that thinks they're signed in, or nag a
      // signed-in user to check an inbox for nothing.
      switch (outcome) {
        case SignUpOutcome.confirmationEmailSent:
          await _showConfirmEmailDialog();
        case SignUpOutcome.signedIn:
          final AuthUser? user = ref.read(authControllerProvider);
          if (user != null) {
            await ref
                .read(profileDaoProvider)
                .linkAccount(userId: user.id, email: user.email);
          }
          if (!mounted) return;
          // Straight into Personal Details — the natural next step, and
          // `pushReplacement` so Back doesn't land on a stale sign-up form.
          context.pushReplacementNamed(Routes.personalDetailsName);
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.messageFor(context.l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConfirmEmailDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.authCheckEmailTitle),
        content: Text(context.l10n.authCheckEmailBody(_email.text.trim())),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.actionGotIt),
          ),
        ],
      ),
    );
    if (mounted) context.pushReplacementNamed(Routes.signInName);
  }
}
