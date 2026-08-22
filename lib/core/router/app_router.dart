import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/sign_in_page.dart';
import '../../features/auth/presentation/sign_up_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/profile/presentation/personal_details_page.dart';
import '../../features/programs/presentation/program_detail_page.dart';
import '../../features/programs/presentation/program_editor_page.dart';
import '../../features/progress/presentation/progress_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/timer/presentation/active_timer_page.dart';
import '../../features/timer/presentation/timer_page.dart';
import '../../features/tracker/presentation/active_workout_page.dart';
import '../../features/tracker/presentation/tracker_page.dart';
import '../../features/tracker/presentation/workout_detail_page.dart';
import '../../features/tracker/presentation/workout_edit_page.dart';
import 'routes.dart';
import 'scaffold_with_nav_bar.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Application router.
///
/// ADR-3: five branches in a [StatefulShellRoute.indexedStack]. Focused-task
/// screens are declared at root level with [rootNavigatorKey] so they cover
/// the shell and hide the bottom bar.
GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    debugLogDiagnostics: true,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.home,
                name: Routes.homeName,
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.tracker,
                name: Routes.trackerName,
                builder: (context, state) => const TrackerPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.library,
                name: Routes.libraryName,
                builder: (context, state) => const LibraryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.timer,
                name: Routes.timerName,
                builder: (context, state) => const TimerPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.progress,
                name: Routes.progressName,
                builder: (context, state) => const ProgressPage(),
              ),
            ],
          ),
        ],
      ),

      // ---- Root-level routes: full screen, no bottom bar (ADR-3) ----
      GoRoute(
        path: Routes.settings,
        name: Routes.settingsName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: Routes.activeWorkout,
        name: Routes.activeWorkoutName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ActiveWorkoutPage(),
      ),
      GoRoute(
        path: Routes.workoutDetail,
        name: Routes.workoutDetailName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => WorkoutDetailPage(
          workoutId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: Routes.workoutEdit,
        name: Routes.workoutEditName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => WorkoutEditPage(
          workoutId: state.pathParameters['id']!,
        ),
      ),
      // Must be registered before `programDetail` — `/program/:id` would
      // otherwise also match `/program/new` (with id='new') first, since
      // go_router resolves routes in list order.
      GoRoute(
        path: Routes.programNew,
        name: Routes.programNewName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProgramEditorPage(),
      ),
      GoRoute(
        path: Routes.programDetail,
        name: Routes.programDetailName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ProgramDetailPage(
          programId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: Routes.programEdit,
        name: Routes.programEditName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ProgramEditorPage(
          programId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: Routes.activeTimer,
        name: Routes.activeTimerName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ActiveTimerPage(),
      ),

      // Accounts (ADR-8). Note the deliberate absence of a `redirect` on
      // this router: an account is optional, and a redirect is the one
      // thing that could stop a cold offline launch from reaching the
      // dashboard.
      GoRoute(
        path: Routes.signIn,
        name: Routes.signInName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: Routes.signUp,
        name: Routes.signUpName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        name: Routes.forgotPasswordName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: Routes.personalDetails,
        name: Routes.personalDetailsName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PersonalDetailsPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('No route for ${state.uri}')),
    ),
  );
}
