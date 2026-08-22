/// Client-side checks for the auth forms.
///
/// Pure and synchronous so the forms can validate on every keystroke without
/// a round trip. These catch typos early; they are not a security boundary —
/// the backend re-validates everything.
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
  static String? email(String? value) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter your email.';
    if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  /// Sign-in only checks presence: an existing account may predate a rule
  /// change, and "your password is too short" on the *sign-in* screen is
  /// both wrong and alarming.
  static String? signInPassword(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password.' : null;

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != original) return 'Passwords don\'t match.';
    return null;
  }
}
