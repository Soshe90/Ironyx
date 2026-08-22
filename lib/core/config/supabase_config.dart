/// Supabase project credentials, supplied at build time.
///
/// Passed with `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_ANON_KEY=...` rather than committed. The anon key
/// is public by design (row-level security is what protects the data), but
/// the project URL still shouldn't be baked into the repository.
///
/// Both default to empty, which is the normal state for a plain
/// `flutter run`, for the test suite, and for CI. [isConfigured] is false in
/// that case and the app runs exactly as it did before accounts existed —
/// ADR-6: capabilities degrade, they never throw.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Whether this build has credentials to talk to a Supabase project.
  ///
  /// Both halves are required: a URL without a key produces a client that
  /// fails on every call, which is worse than no client at all.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
