import '../../../core/l10n/l10n_extension.dart';

/// Client-side checks for the auth forms.
///
/// Pure and synchronous so the forms can validate on every keystroke without
/// a round trip. These catch typos early; they are not a security boundary —
/// the backend re-validates everything.
///
/// Each takes the [AppLocalizations] to phrase its failure with, rather than
/// returning a bare `bool`: the caller would only have to map the failure
/// back onto a message anyway, and doing it here keeps the rule and its
/// wording next to each other.
abstract final class AuthValidators {
  /// Shortest password Supabase accepts by default. Matching it here means
  /// the user sees the rule before submitting rather than after.
  static const int minPasswordLength = 8;

  /// Deliberately loose. The only address that truly validates is one that
  /// receives mail, so this rejects obvious typos (missing `@`, missing dot,
  /// stray spaces) and leaves the rest to the confirmation email. Stricter
  /// regexes reject valid addresses, which is the worse failure.
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Returns null when valid, or a message to show under the field.
  static String? email(String? value, AppLocalizations l10n) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return l10n.authValidatorEmailEmpty;
    if (!_emailPattern.hasMatch(trimmed)) return l10n.authValidatorEmailInvalid;
    return null;
  }

  static String? password(String? value, AppLocalizations l10n) {
    final String password = value ?? '';
    if (password.isEmpty) return l10n.authValidatorPasswordEmpty;
    if (password.length < minPasswordLength) {
      return l10n.authValidatorPasswordTooShort(minPasswordLength);
    }
    return null;
  }

  /// Sign-in only checks presence: an existing account may predate a rule
  /// change, and "your password is too short" on the *sign-in* screen is
  /// both wrong and alarming.
  static String? signInPassword(String? value, AppLocalizations l10n) =>
      (value ?? '').isEmpty ? l10n.authValidatorSignInPasswordEmpty : null;

  static String? confirmPassword(
    String? value,
    String original,
    AppLocalizations l10n,
  ) {
    if ((value ?? '').isEmpty) return l10n.authValidatorConfirmPasswordEmpty;
    if (value != original) return l10n.authValidatorPasswordsDoNotMatch;
    return null;
  }
}
