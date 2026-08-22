import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
import 'widgets/auth_form_scaffold.dart';

/// Sends a password-reset link.
///
/// Completing the reset happens in the browser the link opens, not in the
/// app: handling it in-app needs per-platform deep links, which aren't
/// configured yet. Until they are, the mail's link uses the Supabase
/// project's Site URL.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Reset password',
      intro: _sent
          ? 'If that address has an account, a reset link is on its way. '
              'The link opens in your browser.'
          : 'Enter the email you signed up with and we\'ll send a reset link.',
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: _sent ? 'Send again' : 'Send reset link',
      onSubmit: _submit,
      fields: <Widget>[
        TextFormField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          validator: AuthValidators.email,
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: TextButton(
        onPressed: _busy ? null : () => context.pop(),
        child: const Text('Back to sign in'),
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
      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (failure) {
      // Note: a nonexistent address is *not* surfaced as an error. Supabase
      // returns success either way, on purpose — telling a stranger which
      // emails have accounts is an account-enumeration leak.
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
