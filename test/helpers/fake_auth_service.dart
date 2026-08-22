import 'dart:async';

import 'package:fittrack/features/auth/domain/auth_service.dart';

/// In-memory [AuthService] for tests.
///
/// Exists so nothing in the suite reaches the network: the real
/// `SupabaseAuthService` is only ever constructed by `authServiceProvider`
/// in a configured build, and every test overrides that provider with this.
class FakeAuthService implements AuthService {
  FakeAuthService({
    this.available = true,
    this.requiresEmailConfirmation = false,
    AuthUser? initialUser,
  }) : _current = initialUser;

  /// Accounts registered so far: email to password.
  final Map<String, String> accounts = <String, String>{};

  /// Emails that have been sent a reset link, in order.
  final List<String> passwordResetsSent = <String>[];

  /// When set, the next call fails with this instead of doing its job.
  /// Cleared after it fires, so a test can stage one failure and then
  /// succeed.
  AuthFailureKind? nextFailure;

  /// Mirrors a Supabase project with "confirm email" switched on.
  bool requiresEmailConfirmation;

  final bool available;

  AuthUser? _current;
  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();

  int _nextId = 1;

  @override
  bool get isAvailable => available;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> authStateChanges() => _changes.stream;

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    _maybeFail();
    final String key = email.trim().toLowerCase();
    if (accounts.containsKey(key)) {
      throw const AuthFailure(AuthFailureKind.emailAlreadyRegistered);
    }
    accounts[key] = password;

    if (requiresEmailConfirmation) {
      // Deliberately does not sign anyone in — that is the whole point of
      // the distinction.
      return SignUpOutcome.confirmationEmailSent;
    }
    _emit(_userFor(key, confirmed: true));
    return SignUpOutcome.signedIn;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _maybeFail();
    final String key = email.trim().toLowerCase();
    if (accounts[key] != password) {
      throw const AuthFailure(AuthFailureKind.wrongCredentials);
    }
    final AuthUser user = _userFor(key, confirmed: !requiresEmailConfirmation);
    _emit(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _maybeFail();
    _emit(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _maybeFail();
    // Records unconditionally: the real backend reports success even for an
    // unknown address, to avoid leaking which emails have accounts.
    passwordResetsSent.add(email.trim().toLowerCase());
  }

  /// Simulates the session being restored or dropped from outside the app
  /// (a token refresh, an expiry) to exercise the stream subscription.
  void emitExternalChange(AuthUser? user) => _emit(user);

  void dispose() => _changes.close();

  AuthUser _userFor(String email, {required bool confirmed}) => AuthUser(
        id: 'user-${_nextId++}',
        email: email,
        isEmailConfirmed: confirmed,
      );

  void _emit(AuthUser? user) {
    _current = user;
    _changes.add(user);
  }

  void _maybeFail() {
    final AuthFailureKind? kind = nextFailure;
    if (kind == null) return;
    nextFailure = null;
    throw AuthFailure(kind);
  }
}
