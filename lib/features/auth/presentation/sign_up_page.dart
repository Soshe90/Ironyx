import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/router/routes.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
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
    return AuthFormScaffold(
      title: 'Create account',
      intro: 'Optional. Everything you have already logged stays exactly '
          'where it is.',
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: 'Create account',
      onSubmit: _submit,
      fields: <Widget>[
        TextFormField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          validator: AuthValidators.email,
        ),
        TextFormField(
          controller: _password,
          decoration: InputDecoration(
            labelText: 'Password',
            helperText:
                'At least ${AuthValidators.minPasswordLength} characters',
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          autofillHints: const <String>[AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          validator: AuthValidators.password,
        ),
        TextFormField(
          controller: _confirm,
          decoration: const InputDecoration(labelText: 'Confirm password'),
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          validator: (value) =>
              AuthValidators.confirmPassword(value, _password.text),
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: TextButton(
        onPressed: _busy
            ? null
            : () => context.pushReplacementNamed(Routes.signInName),
        child: const Text('Already have an account? Sign in'),
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
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConfirmEmailDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check your email'),
        content: Text(
          'We sent a confirmation link to ${_email.text.trim()}. Open it, '
          'then come back and sign in.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    if (mounted) context.pushReplacementNamed(Routes.signInName);
  }
}
