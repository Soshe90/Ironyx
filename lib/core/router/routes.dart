/// Route names and paths.
///
/// ADR-3: navigation is by name. No path string literals at call sites.
abstract final class Routes {
  // Branch roots (bottom navigation destinations).
  static const String home = '/';
  static const String homeName = 'home';

  static const String tracker = '/tracker';
  static const String trackerName = 'tracker';

  static const String library = '/library';
  static const String libraryName = 'library';

  static const String timer = '/timer';
  static const String timerName = 'timer';

  static const String progress = '/progress';
  static const String progressName = 'progress';

  // Root-level routes, pushed over the shell. Bottom bar hidden.
  static const String settings = '/settings';
  static const String settingsName = 'settings';

  /// The in-progress workout session (M3).
  static const String activeWorkout = '/workout/active';
  static const String activeWorkoutName = 'activeWorkout';

  /// Read-only summary of a saved workout. `:id` is the workout id.
  static const String workoutDetail = '/workout/:id';
  static const String workoutDetailName = 'workoutDetail';

  /// Edits a saved workout's exercises and sets. `:id` is the workout id.
  static const String workoutEdit = '/workout/:id/edit';
  static const String workoutEditName = 'workoutEdit';

  /// Read-only view of a training program's day-templates. `:id` is the
  /// program id.
  static const String programDetail = '/program/:id';
  static const String programDetailName = 'programDetail';

  /// Creates a new custom program.
  static const String programNew = '/program/new';
  static const String programNewName = 'programNew';

  /// Edits an existing (non-built-in) program's days and exercises.
  /// `:id` is the program id.
  static const String programEdit = '/program/:id/edit';
  static const String programEditName = 'programEdit';

  /// The running interval timer session (M4).
  static const String activeTimer = '/timer/active';
  static const String activeTimerName = 'activeTimer';

  // ---- Accounts (ADR-8) ----
  //
  // Reached from Settings, never forced: signing in is optional and the app
  // is fully usable as a guest, so none of these is a redirect target.

  static const String signIn = '/auth/sign-in';
  static const String signInName = 'signIn';

  static const String signUp = '/auth/sign-up';
  static const String signUpName = 'signUp';

  static const String forgotPassword = '/auth/forgot-password';
  static const String forgotPasswordName = 'forgotPassword';

  /// Name, date of birth, sex, height and current weight.
  static const String personalDetails = '/profile';
  static const String personalDetailsName = 'personalDetails';
}
