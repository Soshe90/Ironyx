import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/deep_links.dart';
import '../../../core/config/supabase_config.dart';
import 'auth_service.dart';
import 'supabase_auth_service.dart';

part 'auth_controller.g.dart';

/// The backend seam. Overridden with a fake in every test — nothing in the
/// suite may reach the network.
///
/// Resolves to [DisabledAuthService] when the build carries no credentials,
/// which is the default for a plain `flutter run` and for CI.
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) {
  if (!SupabaseConfig.isConfigured) return const DisabledAuthService();
  try {
    return SupabaseAuthService(
      sb.Supabase.instance.client,
      // Only where a URL scheme is actually registered. Handing Supabase a
      // redirect that the platform cannot open would strand the user on a
      // page that never loads — worse than the Site URL fallback, which at
      // least fails somewhere they can read.
      redirectTo: _supportsDeepLinks ? DeepLinks.authCallback : null,
    );
  } on Object {
    // Configured but not initialized: `main`'s `Supabase.initialize` failed
    // and chose to keep launching (see `_initSupabase`). Reading `.instance`
    // throws in that state, so degrade to the disabled service rather than
    // crashing the first screen that asks about the account.
    return const DisabledAuthService();
  }
}

/// The two platforms where [DeepLinks.authCallback] is registered.
///
/// The web build has a real origin and is better served by Supabase's Site
/// URL; the desktop builds register no scheme at all, and ADR-6 says a
/// capability that isn't there degrades rather than throws.
bool get _supportsDeepLinks =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Whether this build can offer accounts at all. Lets the UI explain itself
/// instead of showing a sign-in button that can only fail.
@Riverpod(keepAlive: true)
bool authAvailable(Ref ref) => ref.watch(authServiceProvider).isAvailable;

/// The current session.
///
/// Kept alive because the account state is read from Settings and from the
/// profile screen, and re-reading it per route would flash a signed-out
/// state during the rebuild.
///
/// Synchronous by design: [AuthService.currentUser] reads the session
/// Supabase already restored from local storage, so a cold **offline**
/// launch resolves immediately instead of hanging on a network call. That is
/// the property that keeps the app usable on a plane.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  AuthUser? build() {
    final AuthService service = ref.watch(authServiceProvider);

    final subscription = service.authStateChanges().listen((user) {
      state = user;
    });
    ref.onDispose(subscription.cancel);

    return service.currentUser;
  }

  /// Creates an account. Returns how it resolved so the caller can tell
  /// "you're in" from "go confirm your email".
  ///
  /// Throws [AuthFailure]; callers are expected to catch and surface
  /// [AuthFailure.message].
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    final SignUpOutcome outcome = await ref
        .read(authServiceProvider)
        .signUp(email: email, password: password);
    // `authStateChanges` drives `state` when a session was actually
    // created; there is nothing to set here for the confirmation path.
    return outcome;
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final AuthUser user = await ref
        .read(authServiceProvider)
        .signIn(email: email, password: password);
    // Set eagerly rather than waiting for the stream: the caller navigates
    // on return, and the destination must not render a signed-out state for
    // a frame first.
    state = user;
    return user;
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    state = null;
  }

  Future<void> deleteAccount() async {
    await ref.read(authServiceProvider).deleteAccount();
    state = null;
  }

  Future<void> sendPasswordReset(String email) =>
      ref.read(authServiceProvider).sendPasswordReset(email);

  /// Completes a password reset. The recovery session already made the user
  /// the signed-in one, so `state` needs no change.
  Future<void> updatePassword(String newPassword) =>
      ref.read(authServiceProvider).updatePassword(newPassword);
}
