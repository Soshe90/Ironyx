import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/page_body.dart';

/// Shared shell for the three auth screens.
///
/// They differ only in their fields and their primary action, so the title,
/// intro copy, error banner and scroll behaviour live here rather than being
/// copied three times and drifting apart.
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    required this.title,
    required this.intro,
    required this.formKey,
    required this.fields,
    required this.primaryLabel,
    required this.onSubmit,
    required this.busy,
    this.errorMessage,
    this.footer,
    super.key,
  });

  final String title;
  final String intro;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final String primaryLabel;
  final VoidCallback onSubmit;

  /// Disables the form and swaps the action for a spinner while a request
  /// is in flight, so a slow network can't be double-submitted.
  final bool busy;

  /// Failure text shown above the fields. Null when there's nothing wrong.
  final String? errorMessage;

  /// Secondary navigation ("Create one", "Forgot password?").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PageBody(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            children: <Widget>[
              Text(intro, style: AppTypography.caption(theme)),
              const SizedBox(height: AppSpacing.lg),
              if (errorMessage case final String message) ...<Widget>[
                _ErrorBanner(message: message),
                const SizedBox(height: AppSpacing.lg),
              ],
              // Straight on the page: the fields are already filled
              // surfaces, and a card around them only adds a second frame.
              for (final Widget field in fields) ...<Widget>[
                field,
                if (field != fields.last) const SizedBox(height: AppSpacing.md),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: busy ? null : onSubmit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(primaryLabel),
              ),
              if (footer case final Widget widget) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                widget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
