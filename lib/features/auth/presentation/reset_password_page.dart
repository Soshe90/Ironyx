import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
import 'auth_failure_messages.dart';
import 'widgets/auth_form_scaffold.dart';

/// Where a password-reset link lands: choose the new password.
///
/// Opened by `app.dart` when the recovery deep link arrives. The link has
/// already established a recovery session, so no old password is asked for.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _expired = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthFormScaffold(
      title: l10n.authNewPasswordTitle,
      intro: l10n.authNewPasswordIntro,
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: l10n.authNewPasswordSave,
      onSubmit: _submit,
      fields: <Widget>[
        TextFormField(
          controller: _password,
          decoration: InputDecoration(
            labelText: l10n.authFieldNewPassword,
            helperText: l10n.authPasswordHelper(
              AuthValidators.minPasswordLength,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: _obscure ? l10n.authShowPassword : l10n.authHidePassword,
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
      footer: Column(
        children: <Widget>[
          if (_expired)
            TextButton(
              onPressed: () => context.pushReplacementNamed(
                Routes.forgotPasswordName,
              ),
              child: Text(l10n.authNewPasswordRequestNew),
            ),
          TextButton(
            onPressed: _busy ? null : _leave,
            child: Text(l10n.authNewPasswordNotNow),
          ),
        ],
      ),
    );
  }

  /// Back to wherever the link interrupted, or home when this is the only
  /// screen (a cold start from the link).
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(Routes.homeName);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
      _expired = false;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .updatePassword(_password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.authNewPasswordDone)),
      );
      _leave();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.messageFor(context.l10n);
          _expired = failure.kind == AuthFailureKind.recoveryExpired;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
