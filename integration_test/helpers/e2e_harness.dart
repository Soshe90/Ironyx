import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/app.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/router/app_router.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs the real app on a real device, with state that survives a simulated
/// relaunch and is isolated from every other test.
///
/// What is real here, compared with the widget tests under `test/`:
/// SQLite is the device's own, file-backed and on a background isolate, as
/// in production; the exercise and program seeders read the bundled assets;
/// preferences go through the platform channel to disk; notifications,
/// wakelock, audio and haptics are the platform implementations.
///
/// What is not: the database lives in a per-test temporary file rather than
/// the production path, so a run never touches another run's data. And auth
/// is disabled unless a test passes a fake: ADR-8 says nothing in the suite
/// reaches the network, and that includes these tests.
class E2eApp {
  E2eApp._(this._dbFile, this.prefs);

  final File _dbFile;

  /// The real, platform-backed preferences for this run.
  final SharedPreferences prefs;

  AppDatabase? _db;

  /// The database of the currently launched app.
  AppDatabase get db {
    final AppDatabase? db = _db;
    if (db == null) throw StateError('The app is not running.');
    return db;
  }

  /// A clean install: empty database file, empty preferences.
  ///
  /// [prefs] seeds preferences before the first launch. English is pinned
  /// unless the test says otherwise, so text finders do not depend on the
  /// phone's language.
  static Future<E2eApp> install({
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    final SharedPreferences instance = await SharedPreferences.getInstance();
    await instance.clear();
    final Map<String, Object> seeded = <String, Object>{
      'app_locale': 'en',
      ...prefs,
    };
    for (final MapEntry<String, Object> entry in seeded.entries) {
      final Object value = entry.value;
      switch (value) {
        case final bool v:
          await instance.setBool(entry.key, v);
        case final int v:
          await instance.setInt(entry.key, v);
        case final double v:
          await instance.setDouble(entry.key, v);
        case final String v:
          await instance.setString(entry.key, v);
        default:
          throw ArgumentError('Unsupported preference type for ${entry.key}');
      }
    }

    final Directory dir = await Directory.systemTemp.createTemp('ironyx_e2e_');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    return E2eApp._(File('${dir.path}/ironyx.sqlite'), instance);
  }

  /// Starts the app the way `main()` does, over this install's state.
  Future<void> launch(
    WidgetTester tester, {
    AuthService? auth,
    String? initialLocation,
    List<dynamic> overrides = const <dynamic>[],
  }) async {
    // Re-read from disk, so a relaunch sees only what was actually persisted
    // rather than what the in-process cache happened to hold.
    await prefs.reload();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((ref) {
            final AppDatabase db = AppDatabase.withExecutor(
              NativeDatabase.createInBackground(_dbFile),
            );
            _db = db;
            ref.onDispose(db.close);
            return db;
          }),
          // Pinned even when no fake is given, so a run that happens to
          // carry Supabase credentials still cannot reach the network.
          authServiceProvider
              .overrideWithValue(auth ?? const DisabledAuthService()),
          ...overrides.cast(),
        ],
        child: IronyxApp(
          router: initialLocation == null
              ? null
              : createRouter(initialLocation: initialLocation),
        ),
      ),
    );
    await tester.pump();
  }

  /// Ends the process as far as the app can tell: the provider container is
  /// disposed, the database is closed, and nothing in memory carries over.
  ///
  /// This is a simulated kill. A real `am force-stop` would also end the test
  /// runner, so it cannot be asserted from inside it; C6 covers that by hand.
  Future<void> kill(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Lets the database's background isolate finish closing.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    _db = null;
  }

  /// The running app's provider container.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IronyxApp)));
}

/// Runs real I/O (a database query, a file read) from a test body.
Future<T> io<T>(WidgetTester tester, Future<T> Function() work) async =>
    (await tester.runAsync(work)) as T;

/// Pumps frames until [finder] matches, or fails after [timeout].
///
/// `pumpAndSettle` is not usable against this app: loading placeholders
/// animate forever by design, so it would never settle. This waits on the
/// condition the test actually cares about.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Stopwatch clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for $finder');
}

/// The inverse of [pumpUntilFound].
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Stopwatch clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for $finder to go');
}

/// Pumps frames for [duration] of real time.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final Stopwatch clock = Stopwatch()..start();
  while (clock.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Finds the [Semantics] widget the app labelled [label].
///
/// Matches the widget rather than the semantics tree, so it works without
/// turning semantics on, and matches exactly: `find.bySemanticsLabel` would
/// also match a node that merged this label with a child's.
Finder semanticsLabelled(String label) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == label,
      description: 'Semantics labelled "$label"',
    );

/// Brings [finder] on screen by scrolling the first scrollable, then taps it.
Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}
