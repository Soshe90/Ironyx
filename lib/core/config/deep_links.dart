/// The custom URL scheme Supabase sends users back to from its emails.
///
/// Without this, Supabase falls back to the project's Site URL — which
/// defaults to `http://localhost:3000` and produces a browser error on a
/// phone, after the confirmation has already succeeded server-side. The
/// account works; it just looks broken.
///
/// The scheme is the Android `applicationId` / iOS bundle identifier
/// verbatim, because a custom scheme is first-come-first-served on a device:
/// a generic `ironyx://` could be claimed by any other app installed
/// alongside this one, and Android resolves the collision by asking the user
/// which app should handle their login link.
///
/// Registered in three places that must agree, or the link dead-ends:
/// - `android/app/src/main/AndroidManifest.xml` (intent filter)
/// - `ios/Runner/Info.plist` (`CFBundleURLTypes`)
/// - the Supabase dashboard's **Redirect URLs** allow-list, which rejects
///   any `redirect_to` it has not been told about and silently falls back to
///   the Site URL.
abstract final class DeepLinks {
  static const String scheme = 'com.soshe90.ironyx';

  static const String _host = 'login-callback';

  /// Where email confirmation and password-reset links land.
  ///
  /// `supabase_flutter` watches for incoming links itself once the platform
  /// registration above is in place, exchanges the `?code=` for a session and
  /// emits it on `onAuthStateChange` — which `AuthController` already
  /// listens to. No manual parsing is needed on the Dart side.
  static const String authCallback = '$scheme://$_host';
}
