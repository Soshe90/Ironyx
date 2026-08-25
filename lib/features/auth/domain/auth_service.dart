/// The app's own view of an authenticated account.
///
/// Deliberately not Supabase's `User`: nothing outside
/// `supabase_auth_service.dart` should reference the vendor SDK, so that
/// tests can run against a fake and a future backend swap stays local.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.isEmailConfirmed,
  });

  /// The backend's stable user id, stored locally as `profiles.remote_user_id`.
  final String id;
  final String email;

  /// False between signing up and clicking the confirmation link, when the
  /// project requires email confirmation.
  final bool isEmailConfirmed;
}

/// Why an auth call didn't succeed.
///
/// A closed set rather than a raw message so the UI can decide both wording
/// and affordances (offering "reset password" on [wrongCredentials], say)
/// without string-matching backend errors.
enum AuthFailureKind {
  /// Email or password didn't match an account.
  wrongCredentials,

  /// Sign-up hit an address that already has an account.
  emailAlreadyRegistered,

  /// The backend rejected the password as too weak.
  weakPassword,

  /// The backend refused the address itself. Supabase rejects a set of
  /// domains outright (`example.com` among them), independently of whether
  /// the address is well-formed, so client-side validation cannot predict
  /// this and the user needs telling which field is at fault.
  emailRejected,

  /// New sign-ups are switched off for this project.
  signUpDisabled,

  /// The address isn't confirmed yet and the project requires confirmation.
  emailNotConfirmed,

  /// Too many attempts; the backend is asking us to back off.
  rateLimited,

  /// No network, DNS failure, timeout — anything that means "we never
  /// reached the server". Distinct from the rest because it's the one an
  /// offline-first app must handle gracefully rather than treat as an error
  /// in the user's input.
  offline,

  /// This build has no Supabase credentials, so accounts are unavailable.
  notConfigured,

  /// Anything unrecognised.
  unknown,
}

/// A failed auth call. Thrown by [AuthService] implementations.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, {this.detail});

  final AuthFailureKind kind;

  /// The backend's own message, kept for logs. Never shown verbatim — the
  /// user-facing wording comes from `AuthFailureL10n.messageFor` in the
  /// presentation layer, which is where the translations live.
  final String? detail;

  @override
  String toString() => 'AuthFailure(${kind.name}${detail == null ? '' : ': '
      '$detail'})';
}

/// What [AuthService.signUp] resulted in.
///
/// Sign-up has two legitimate outcomes and conflating them is a real bug:
/// when the project requires email confirmation the user is *not* signed in
/// yet, and telling them they are leaves them stuck.
enum SignUpOutcome { signedIn, confirmationEmailSent }

/// Email/password authentication, abstracted away from the backend.
///
/// Implementations must translate transport and vendor errors into
/// [AuthFailure] — callers should never see a vendor exception type.
abstract interface class AuthService {
  /// Whether this build can talk to an auth backend at all. False for
  /// `DisabledAuthService`, which lets the UI explain itself rather than
  /// offering a sign-in button that can only fail.
  bool get isAvailable;

  /// The session restored at startup, if any. Reads local storage only —
  /// safe to call offline, and safe to call before the first frame.
  AuthUser? get currentUser;

  /// Emits on sign-in, sign-out, and token refresh. Emits null when signed
  /// out. Does not replay the current value on listen; read [currentUser]
  /// for the initial state.
  Stream<AuthUser?> authStateChanges();

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  });

  Future<AuthUser> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);
}

/// Stand-in used when [SupabaseConfig.isConfigured] is false.
///
/// Every call fails with [AuthFailureKind.notConfigured] instead of
/// constructing a client that would throw on first use. This is what keeps a
/// credential-free `flutter run` and the whole test suite working unchanged.
class DisabledAuthService implements AuthService {
  const DisabledAuthService();

  @override
  bool get isAvailable => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async =>
      throw const AuthFailure(AuthFailureKind.notConfigured);

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async =>
      throw const AuthFailure(AuthFailureKind.notConfigured);

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(String email) async =>
      throw const AuthFailure(AuthFailureKind.notConfigured);
}
