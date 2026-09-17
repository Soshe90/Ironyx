import 'package:ironyx/core/providers.dart';

/// Overrides that stop the real seeders from touching a test's database.
///
/// A test that seeds its own small catalogue needs the app's seeders to do
/// nothing at all. Bumping `exercise_seed_version` in preferences is not
/// enough and hasn't been for a while: [ExerciseSeeder] also checks that the
/// catalogue actually contains a row per asset entry, so that an interrupted
/// seed cannot leave the library half-populated. On a fixture database that
/// count is always short, so the seeder runs anyway and replaces the test's
/// data with all 151 bundled exercises.
///
/// Overriding the notifier is the honest way to say "not in this test".
///
/// Typed `List<dynamic>` because Riverpod 3 does not export `Override` from
/// its public barrel; `pumpApp` casts the list back on the way into
/// `ProviderScope`, which is the same dance it already does for its own
/// `overrides` parameter.
List<dynamic> stubSeeders() => <dynamic>[
      exerciseSeederProvider.overrideWith(_NoopExerciseSeeder.new),
      programSeederProvider.overrideWith(_NoopProgramSeeder.new),
    ];

class _NoopExerciseSeeder extends ExerciseSeeder {
  @override
  Future<void> build() async {}
}

class _NoopProgramSeeder extends ProgramSeeder {
  @override
  Future<void> build() async {}
}
