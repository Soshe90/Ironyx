import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
import 'auth_failure_messages.dart';
import 'widgets/auth_form_scaffold.dart';

/// Signs an existing account in. Reached from Settings; never forced.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AuthFormScaffold(
      title: l10n.authSignInTitle,
      intro: l10n.authSignInIntro,
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: l10n.authSignInTitle,
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
          autofillHints: const <String>[AutofillHints.password],
          textInputAction: TextInputAction.done,
          // Presence only — see AuthValidators.signInPassword.
          validator: (String? value) =>
              AuthValidators.signInPassword(value, l10n),
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: Column(
        children: <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => context.pushNamed(Routes.forgotPasswordName),
            child: Text(l10n.authForgotPasswordLink),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _busy
                ? null
                : () => context.pushReplacementNamed(Routes.signUpName),
            child: Text(l10n.authNoAccountCreateOne),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final AppLocalizations l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final AuthUser user =
          await ref.read(authControllerProvider.notifier).signIn(
                email: _email.text,
                password: _password.text,
              );
      // Attach the account to the profile that already holds this device's
      // history, rather than starting a second one.
      await ref
          .read(profileDaoProvider)
          .linkAccount(userId: user.id, email: user.email);

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.authSignedIn)));
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.messageFor(l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
