import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth_service.dart';

/// The only file in the app allowed to reference `supabase_flutter`.
///
/// Its whole job is translating the SDK's surface into [AuthUser] /
/// [AuthFailure] so nothing downstream — controllers, widgets, tests — has
/// to know which backend is behind the seam.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client, {this.redirectTo});

  final sb.SupabaseClient _client;

  /// Deep link that confirmation and password-reset mails send the user back
  /// to. One value for both: they are the same journey — leave the app, tap
  /// a link in a mail client, come back signed in.
  ///
  /// Null on platforms with no URL scheme registered (and in tests), in which
  /// case Supabase falls back to the project's Site URL. That degrades to the
  /// old behaviour rather than failing: the confirmation itself happens on
  /// Supabase's side before the redirect is ever followed, so the account is
  /// confirmed either way — the user just lands on a dead page instead of
  /// back in the app.
  final String? redirectTo;

  sb.GoTrueClient get _auth => _client.auth;

  @override
  bool get isAvailable => true;

  @override
  AuthUser? get currentUser => _toAuthUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.onAuthStateChange.map((state) => _toAuthUser(state.session?.user));

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final sb.AuthResponse response = await _auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectTo,
      );
      // A null session with a non-null user means the project requires
      // email confirmation: the account exists but nobody is signed in yet.
      // Reporting this as success would strand the user on a screen that
      // thinks they're logged in.
      return response.session == null
          ? SignUpOutcome.confirmationEmailSent
          : SignUpOutcome.signedIn;
    });
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final sb.AuthResponse response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final AuthUser? user = _toAuthUser(response.user);
      if (user == null) {
        throw const AuthFailure(AuthFailureKind.unknown,
            detail: 'Sign-in returned no user.');
      }
      return user;
    });
  }

  @override
  Future<void> signOut() {
    // Scoped to this device: signing out on a phone shouldn't kill the
    // session on a tablet the user left signed in.
    return _guard(() => _auth.signOut(scope: sb.SignOutScope.local));
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _guard(
      () => _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectTo,
      ),
    );
  }

  static AuthUser? _toAuthUser(sb.User? user) {
    if (user == null) return null;
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      isEmailConfirmed: user.emailConfirmedAt != null,
    );
  }

  /// Runs [action], mapping every failure mode onto [AuthFailure].
  ///
  /// Nothing may escape this: an unmapped exception reaching the UI is the
  /// difference between "check your connection" and a red error screen
  /// mid-workout.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on sb.AuthException catch (error) {
      // gotrue funnels *every* transport failure into
      // AuthRetryableFetchException — a paused project, an unresolvable
      // host, a TLS error and a CORS rejection all arrive identically. The
      // user-facing message has to stay generic, but swallowing the
      // underlying text entirely leaves nothing to debug from, so log it.
      _log(error);
      // Transport failures don't need a separate branch: gotrue's fetch
      // layer catches everything the socket throws and re-raises it as
      // AuthRetryableFetchException, which `_kindOf` maps to `offline`.
      // Catching `dart:io`'s SocketException here would be both redundant
      // and fatal to the web build (ADR-6) — the import alone breaks it.
      throw AuthFailure(_kindOf(error), detail: error.message);
    } on TimeoutException catch (error) {
      _log(error);
      throw AuthFailure(AuthFailureKind.offline, detail: error.message);
    } on Object catch (error) {
      _log(error);
      throw AuthFailure(AuthFailureKind.unknown, detail: error.toString());
    }
  }

  /// Debug-only. Auth errors can carry an email address, so this must never
  /// reach a release log.
  static void _log(Object error) {
    if (kDebugMode) debugPrint('[auth] $error');
  }

  static AuthFailureKind _kindOf(sb.AuthException error) {
    // Thrown for DNS failures, refused connections and timeouts — the SDK's
    // own signal that the request never reached the server.
    if (error is sb.AuthRetryableFetchException) {
      return AuthFailureKind.offline;
    }
    if (error is sb.AuthWeakPasswordException) {
      return AuthFailureKind.weakPassword;
    }
    // Matched on the wire code rather than the SDK's `ErrorCode` enum: the
    // enum omits `invalid_credentials`, which is the single most common
    // failure there is.
    return switch (error.code) {
      'invalid_credentials' ||
      'user_not_found' =>
        AuthFailureKind.wrongCredentials,
      'email_exists' ||
      'user_already_exists' =>
        AuthFailureKind.emailAlreadyRegistered,
      'weak_password' => AuthFailureKind.weakPassword,
      'email_not_confirmed' => AuthFailureKind.emailNotConfirmed,
      // Supabase blocks certain domains outright, so a perfectly well-formed
      // address can still be refused. Without this the user gets a generic
      // "something went wrong" and no idea which field to change.
      'email_address_invalid' => AuthFailureKind.emailRejected,
      'signup_disabled' ||
      'email_provider_disabled' =>
        AuthFailureKind.signUpDisabled,
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' =>
        AuthFailureKind.rateLimited,
      'request_timeout' => AuthFailureKind.offline,
      _ => AuthFailureKind.unknown,
    };
  }
}
