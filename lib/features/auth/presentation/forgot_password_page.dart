import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
import 'auth_failure_messages.dart';
import 'widgets/auth_form_scaffold.dart';

/// Sends a password-reset link.
///
/// Supabase returns the user through the registered platform callback when
/// configured. The callback restores the recovery session and `app.dart`
/// opens `ResetPasswordPage` to finish the reset.
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
    final AppLocalizations l10n = context.l10n;

    return AuthFormScaffold(
      title: l10n.authResetPasswordTitle,
      intro: _sent ? l10n.authResetSentIntro : l10n.authResetIntro,
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: _sent ? l10n.authResetSendAgain : l10n.authResetSendLink,
      onSubmit: _submit,
      fields: <Widget>[
        TextFormField(
          controller: _email,
          decoration: InputDecoration(labelText: l10n.authFieldEmail),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          validator: (String? value) => AuthValidators.email(value, l10n),
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: TextButton(
        onPressed: _busy ? null : () => context.pop(),
        child: Text(l10n.authBackToSignIn),
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
      if (mounted) setState(() => _error = failure.messageFor(context.l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
