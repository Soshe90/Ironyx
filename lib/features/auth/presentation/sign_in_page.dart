import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/auth_controller.dart';
import '../domain/auth_service.dart';
import '../domain/auth_validators.dart';
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
    return AuthFormScaffold(
      title: 'Sign in',
      intro: 'Your workouts stay on this device either way — an account just '
          'keeps your details with you.',
      formKey: _formKey,
      busy: _busy,
      errorMessage: _error,
      primaryLabel: 'Sign in',
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
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          autofillHints: const <String>[AutofillHints.password],
          textInputAction: TextInputAction.done,
          // Presence only — see AuthValidators.signInPassword.
          validator: AuthValidators.signInPassword,
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
      footer: Column(
        children: <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => context.pushNamed(Routes.forgotPasswordName),
            child: const Text('Forgot password?'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed:
                _busy ? null : () => context.pushReplacementNamed(Routes.signUpName),
            child: const Text('No account? Create one'),
          ),
        ],
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
      final AuthUser user = await ref.read(authControllerProvider.notifier).signIn(
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
          .showSnackBar(const SnackBar(content: Text('Signed in')));
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
