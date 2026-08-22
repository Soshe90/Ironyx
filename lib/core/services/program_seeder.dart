import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/program_dao.dart';
import '../providers.dart';

part 'program_seeder.g.dart';

const _uuid = Uuid();

/// A compact specification for one exercise row in a built-in program.
typedef _SeedExercise = (String exerciseId, int sets, String reps);

/// A compact specification for one day-template in a built-in program.
typedef _SeedDay = ({
  String templateId,
  String templateName,
  String dayName,
  List<_SeedExercise> exercises,
});

/// Seeds built-in training programs (Full Body, Upper/Lower, Push/Pull/
/// Legs) so a new user sees real, startable programs immediately.
///
/// Idempotent via a SharedPreferences version key. Built-in programs are
/// deleted and re-inserted when the seed version advances; user-created
/// programs are never touched.
@Riverpod(keepAlive: true)
class ProgramSeeder extends _$ProgramSeeder {
  static const String _versionKey = 'program_seed_version';
  static const int _currentVersion = 1;

  @override
  Future<void> build() async {
    // Programs reference exercises by id with a RESTRICT foreign key, so the
    // exercise catalogue must be seeded first.
    await ref.watch(exerciseSeederProvider.future);

    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getInt(_versionKey) ?? 0;
    if (stored >= _currentVersion) return;

    final dao = ref.read(programDaoProvider);
    await dao.deleteBuiltInPrograms();

    // Editing a built-in converts it to a custom program (keeping its name),
    // so a surviving program can now own a name this seed wants. Skip those
    // rather than hitting the UNIQUE constraint on `programs_table.name` —
    // an uncaught failure here blocks app startup, and the user's edited
    // copy is the one they'd rather keep anyway.
    final Set<String> taken = await dao.allProgramNames();

    for (final (id, name, splitType, dayCount, days) in <
        (String, String, String, int, List<_SeedDay>)>[
      ('builtin_full_body', 'Full Body', 'fullBody', 3, _fullBodyDays()),
      ('builtin_upper_lower', 'Upper / Lower', 'upperLower', 4,
          _upperLowerDays()),
      ('builtin_ppl', 'Push / Pull / Legs', 'ppl', 3, _pplDays()),
    ]) {
      if (taken.contains(name)) continue;
      await dao.insertProgram(
        _programCompanion(id, name, splitType: splitType, dayCount: dayCount),
        _days(id, days),
      );
    }

    await prefs.setInt(_versionKey, _currentVersion);
  }

  /// Clears the seed-version marker so the next [build] re-inserts the
  /// built-in programs from scratch. Used by the "delete all data" flow,
  /// which removes every program (built-in and user) along with their
  /// templates — without this, the version gate would think built-ins are
  /// already seeded and never restore them.
  Future<void> resetSeedVersion() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_versionKey);
  }

  ProgramsTableCompanion _programCompanion(
    String id,
    String name, {
    required String splitType,
    required int dayCount,
  }) {
    final now = DateTime.now().toUtc();
    return ProgramsTableCompanion.insert(
      id: id,
      name: name,
      description: Value(_description(splitType, dayCount)),
      splitType: Value(splitType),
      createdAt: now,
      updatedAt: now,
      isBuiltIn: const Value(true),
    );
  }

  List<ProgramDayInsert> _days(
    String programId,
    List<_SeedDay> days,
  ) {
    final now = DateTime.now().toUtc();
    return [
      for (var i = 0; i < days.length; i++)
        ProgramDayInsert(
          id: '${programId}_pt_$i',
          dayName: days[i].dayName,
          orderIndex: i,
          template: TemplatesTableCompanion.insert(
            id: days[i].templateId,
            name: days[i].templateName,
            description: const Value.absent(),
            createdAt: now,
            updatedAt: now,
            isBuiltIn: const Value(true),
          ),
          exercises: [
            for (var j = 0; j < days[i].exercises.length; j++)
              TemplateExercisesTableCompanion.insert(
                id: _uuid.v4(),
                templateId: days[i].templateId,
                exerciseId: days[i].exercises[j].$1,
                orderIndex: j,
                targetSets: days[i].exercises[j].$2,
                targetReps: Value(days[i].exercises[j].$3),
              ),
          ],
        ),
    ];
  }

  String _description(String splitType, int dayCount) => switch (splitType) {
        'fullBody' => 'Full body · $dayCount days/week',
        'upperLower' => 'Upper / lower · $dayCount days/week',
        'ppl' => 'Push / pull / legs · $dayCount days/week',
        _ => '$dayCount days/week',
      };
}

List<_SeedDay> _fullBodyDays() => [
      (
        templateId: 'builtin_fb_a',
        templateName: 'Full Body A',
        dayName: 'Workout A',
        exercises: [
          ('ex_025', 3, '6-8'),
          ('ex_001', 3, '8-10'),
          ('ex_009', 3, '8-12'),
          ('ex_014', 3, '8-10'),
        ],
      ),
      (
        templateId: 'builtin_fb_b',
        templateName: 'Full Body B',
        dayName: 'Workout B',
        exercises: [
          ('ex_031', 3, '5'),
          ('ex_003', 3, '8-10'),
          ('ex_007', 3, '6-10'),
          ('ex_016', 3, '12-15'),
        ],
      ),
      (
        templateId: 'builtin_fb_c',
        templateName: 'Full Body C',
        dayName: 'Workout C',
        exercises: [
          ('ex_026', 3, '6-8'),
          ('ex_014', 3, '8-10'),
          ('ex_012', 3, '10-12'),
          ('ex_019', 3, '10-15'),
        ],
      ),
    ];

List<_SeedDay> _upperLowerDays() => [
      (
        templateId: 'builtin_ul_upper_a',
        templateName: 'Upper A',
        dayName: 'Upper A',
        exercises: [
          ('ex_001', 4, '6-8'),
          ('ex_009', 4, '8-10'),
          ('ex_014', 3, '8-10'),
          ('ex_019', 3, '10-12'),
        ],
      ),
      (
        templateId: 'builtin_ul_lower_a',
        templateName: 'Lower A',
        dayName: 'Lower A',
        exercises: [
          ('ex_025', 4, '6-8'),
          ('ex_030', 3, '8-10'),
          ('ex_036', 3, '10-12'),
          ('ex_037', 4, '12-15'),
        ],
      ),
      (
        templateId: 'builtin_ul_upper_b',
        templateName: 'Upper B',
        dayName: 'Upper B',
        exercises: [
          ('ex_007', 4, '6-10'),
          ('ex_002', 4, '8-10'),
          ('ex_016', 3, '12-15'),
          ('ex_024', 3, '10-12'),
        ],
      ),
      (
        templateId: 'builtin_ul_lower_b',
        templateName: 'Lower B',
        dayName: 'Lower B',
        exercises: [
          ('ex_031', 3, '5'),
          ('ex_034', 3, '10-12'),
          ('ex_035', 3, '12-15'),
          ('ex_037', 4, '12-15'),
        ],
      ),
    ];

List<_SeedDay> _pplDays() => [
      (
        templateId: 'builtin_ppl_push',
        templateName: 'Push',
        dayName: 'Push Day',
        exercises: [
          ('ex_001', 4, '6-8'),
          ('ex_003', 3, '8-10'),
          ('ex_014', 3, '8-10'),
          ('ex_024', 3, '10-12'),
        ],
      ),
      (
        templateId: 'builtin_ppl_pull',
        templateName: 'Pull',
        dayName: 'Pull Day',
        exercises: [
          ('ex_031', 3, '5'),
          ('ex_007', 4, '6-10'),
          ('ex_012', 3, '10-12'),
          ('ex_019', 3, '10-12'),
        ],
      ),
      (
        templateId: 'builtin_ppl_legs',
        templateName: 'Legs',
        dayName: 'Leg Day',
        exercises: [
          ('ex_025', 4, '6-8'),
          ('ex_034', 3, '10-12'),
          ('ex_036', 3, '10-12'),
          ('ex_037', 4, '12-15'),
        ],
      ),
    ];
