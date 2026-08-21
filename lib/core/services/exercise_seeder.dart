import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../providers.dart';

part 'exercise_seeder.g.dart';

const _uuid = Uuid();

/// Seeds the exercise database from the JSON asset.
///
/// Runs once on first launch, guarded by a `seed_version` key in
/// SharedPreferences. If the seed version in the JSON is newer than the
/// stored version, re-seeds. The seed file is exercise-centric (each
/// exercise object nests its own muscles/equipment/instructions/aliases/
/// media/tags/sources) even though the database underneath is normalized
/// — far easier to hand-author and review than fully flattened per-table
/// files.
@Riverpod(keepAlive: true)
class ExerciseSeeder extends _$ExerciseSeeder {
  static const String _seedVersionKey = 'exercise_seed_version';
  static const String _seedAssetPath = 'assets/data/exercises_seed.json';

  @override
  Future<void> build() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final storedVersion = prefs.getInt(_seedVersionKey) ?? 0;

    final jsonString = await rootBundle.loadString(_seedAssetPath);
    final Map<String, dynamic> seedData =
        jsonDecode(jsonString) as Map<String, dynamic>;
    final int currentVersion = seedData['seedVersion'] as int;

    if (storedVersion >= currentVersion) return;

    await _seedDatabase(seedData, currentVersion);
    await prefs.setInt(_seedVersionKey, currentVersion);
  }

  Future<void> _seedDatabase(Map<String, dynamic> seedData, int version) async {
    final exerciseDao = ref.read(exerciseDaoProvider);
    final muscleDao = ref.read(muscleDaoProvider);
    final equipmentDao = ref.read(equipmentDaoProvider);

    // Taxonomy first — the per-exercise links below reference these by id.
    final muscles = seedData['muscles'] as List<dynamic>? ?? const [];
    await muscleDao.upsertAll([
      for (final raw in muscles) _muscleCompanion(raw as Map<String, dynamic>),
    ]);

    final equipment = seedData['equipment'] as List<dynamic>? ?? const [];
    await equipmentDao.upsertAll([
      for (final raw in equipment)
        _equipmentCompanion(raw as Map<String, dynamic>),
    ]);

    // Drop exercises that fell out of this seed version (skips any a
    // logged workout still references — see ExerciseDao.deleteOrphanedSeed).
    await exerciseDao.deleteOrphanedSeed(version);

    final exercises = seedData['exercises'] as List<dynamic>? ?? const [];
    for (final raw in exercises) {
      final json = raw as Map<String, dynamic>;
      final id = json['id'] as String;

      // The exercise row itself is upserted (never delete-then-insert —
      // see ExerciseDao.upsertExercises). Its child rows have no inbound
      // foreign keys from outside the exercise feature, so a plain
      // replace (delete-for-this-exercise, then insert) is safe for them.
      await exerciseDao.upsertExercises([_exerciseCompanion(json, version)]);
      await exerciseDao.replaceMuscleLinks(id, _muscleLinks(id, json));
      await exerciseDao.replaceEquipmentLinks(id, _equipmentLinks(id, json));
      await exerciseDao.replaceInstructions(id, _instructionSteps(id, json));
      await exerciseDao.replaceAliases(id, _aliasRows(id, json));
      await exerciseDao.replaceMedia(id, _mediaRows(id, json));
      await exerciseDao.replaceTags(id, _tagRows(id, json));
      await exerciseDao.replaceSources(id, _sourceRows(id, json));
    }
  }

  MusclesTableCompanion _muscleCompanion(Map<String, dynamic> json) =>
      MusclesTableCompanion.insert(
        id: json['id'] as String,
        name: json['name'] as String,
        displayName: json['displayName'] as String,
        region: json['region'] == null
            ? const Value.absent()
            : Value(json['region'] as String),
        parentId: json['parentId'] == null
            ? const Value.absent()
            : Value(json['parentId'] as String),
      );

  EquipmentTableCompanion _equipmentCompanion(Map<String, dynamic> json) =>
      EquipmentTableCompanion.insert(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] == null
            ? const Value.absent()
            : Value(json['category'] as String),
      );

  ExercisesTableCompanion _exerciseCompanion(
    Map<String, dynamic> json,
    int version,
  ) {
    return ExercisesTableCompanion.insert(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: Value(json['description'] as String? ?? ''),
      category: json['category'] as String,
      difficulty: json['difficulty'] as String,
      movementPattern: json['movementPattern'] as String,
      forceType: json['forceType'] == null
          ? const Value.absent()
          : Value(json['forceType'] as String),
      mechanic: json['mechanic'] == null
          ? const Value.absent()
          : Value(json['mechanic'] as String),
      isUnilateral: Value(json['isUnilateral'] as bool? ?? false),
      isBodyweight: Value(json['isBodyweight'] as bool? ?? false),
      seedVersion: version,
    );
  }

  List<ExerciseMusclesTableCompanion> _muscleLinks(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final muscles = json['muscles'] as List<dynamic>? ?? const [];
    return [
      for (final raw in muscles)
        ExerciseMusclesTableCompanion.insert(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          muscleId: (raw as Map<String, dynamic>)['muscleId'] as String,
          role: raw['role'] as String,
        ),
    ];
  }

  List<ExerciseEquipmentTableCompanion> _equipmentLinks(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final equipment = json['equipment'] as List<dynamic>? ?? const [];
    return [
      for (final raw in equipment)
        ExerciseEquipmentTableCompanion.insert(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          equipmentId: (raw as Map<String, dynamic>)['equipmentId'] as String,
          isRequired: Value(raw['isRequired'] as bool? ?? true),
        ),
    ];
  }

  List<ExerciseInstructionsTableCompanion> _instructionSteps(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final steps = json['instructions'] as List<dynamic>? ?? const [];
    return [
      for (var i = 0; i < steps.length; i++)
        ExerciseInstructionsTableCompanion.insert(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          stepNumber: i + 1,
          instruction: steps[i] as String,
        ),
    ];
  }

  List<ExerciseAliasesTableCompanion> _aliasRows(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final aliases = json['aliases'] as List<dynamic>? ?? const [];
    return [
      for (final alias in aliases)
        ExerciseAliasesTableCompanion.insert(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          alias: alias as String,
        ),
    ];
  }

  List<ExerciseMediaTableCompanion> _mediaRows(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final media = json['media'] as List<dynamic>? ?? const [];
    return [
      for (final raw in media)
        _mediaCompanion(exerciseId, raw as Map<String, dynamic>),
    ];
  }

  ExerciseMediaTableCompanion _mediaCompanion(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    return ExerciseMediaTableCompanion.insert(
      id: _uuid.v4(),
      exerciseId: exerciseId,
      type: json['type'] as String,
      url: json['url'] == null
          ? const Value.absent()
          : Value(json['url'] as String),
      localAsset: json['localAsset'] == null
          ? const Value.absent()
          : Value(json['localAsset'] as String),
      sortOrder: Value(json['sortOrder'] as int? ?? 0),
      license: json['license'] == null
          ? const Value.absent()
          : Value(json['license'] as String),
      attribution: json['attribution'] == null
          ? const Value.absent()
          : Value(json['attribution'] as String),
      source: json['source'] == null
          ? const Value.absent()
          : Value(json['source'] as String),
    );
  }

  List<ExerciseTagsTableCompanion> _tagRows(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final tags = json['tags'] as List<dynamic>? ?? const [];
    return [
      for (final tag in tags)
        ExerciseTagsTableCompanion.insert(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          tag: tag as String,
        ),
    ];
  }

  List<ExerciseSourcesTableCompanion> _sourceRows(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    final sources = json['sources'] as List<dynamic>? ?? const [];
    return [
      for (final raw in sources)
        _sourceCompanion(exerciseId, raw as Map<String, dynamic>),
    ];
  }

  ExerciseSourcesTableCompanion _sourceCompanion(
    String exerciseId,
    Map<String, dynamic> json,
  ) {
    return ExerciseSourcesTableCompanion.insert(
      id: _uuid.v4(),
      exerciseId: exerciseId,
      sourceName: json['sourceName'] as String,
      sourceUrl: json['sourceUrl'] == null
          ? const Value.absent()
          : Value(json['sourceUrl'] as String),
      sourceExerciseId: json['sourceExerciseId'] == null
          ? const Value.absent()
          : Value(json['sourceExerciseId'] as String),
      license: json['license'] == null
          ? const Value.absent()
          : Value(json['license'] as String),
      attribution: json['attribution'] == null
          ? const Value.absent()
          : Value(json['attribution'] as String),
      usedFor: json['usedFor'] == null
          ? const Value.absent()
          : Value(json['usedFor'] as String),
    );
  }

  /// Forces a re-seed (for testing or manual refresh).
  Future<void> forceReseed() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_seedVersionKey);
    ref.invalidateSelf();
  }
}
