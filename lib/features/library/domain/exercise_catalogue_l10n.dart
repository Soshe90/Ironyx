import 'package:flutter/widgets.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/tables/equipment.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/database/tables/muscles.dart';
import '../../../core/formatters/search_fold.dart';
import '../../../core/l10n/l10n_extension.dart';
import 'exercise_catalogue_ar.dart';
import 'exercise_instructions_ar_1.dart';
import 'exercise_instructions_ar_10.dart';
import 'exercise_instructions_ar_2.dart';
import 'exercise_instructions_ar_3.dart';
import 'exercise_instructions_ar_4.dart';
import 'exercise_instructions_ar_5.dart';
import 'exercise_instructions_ar_6.dart';
import 'exercise_instructions_ar_7.dart';
import 'exercise_instructions_ar_8.dart';
import 'exercise_instructions_ar_9.dart';

/// Localized display names for catalogue rows.
///
/// The database stores one name per exercise, in English, because that is
/// what the seed ships and what an id-preserving upsert has to keep stable.
/// Translating at the point of display — rather than translating the rows —
/// means switching language re-labels the catalogue instantly, a re-seed
/// cannot clobber translations, and a user-created exercise keeps the name
/// its author gave it.
extension ExerciseL10n on Exercise {
  String displayName(BuildContext context) =>
      _lookup(context, kExerciseNamesAr, slug) ?? name;
}

extension MuscleL10n on Muscle {
  String localizedName(BuildContext context) =>
      _lookup(context, kMuscleNamesAr, id) ?? displayName;
}

extension EquipmentL10n on Equipment {
  String localizedName(BuildContext context) =>
      _lookup(context, kEquipmentNamesAr, id) ?? name;
}

/// Translates a muscle-group name for a query result that carries only the
/// id and the stored English name (the Progress analytics), rather than a
/// [Muscle] for [MuscleL10n.localizedName].
String localizedMuscleName(
  BuildContext context,
  String muscleId,
  String fallbackName,
) =>
    _lookup(context, kMuscleNamesAr, muscleId) ?? fallbackName;

/// An exercise summary's equipment, translated: each name looked up by
/// its id (`kEquipmentNamesAr` is keyed by id), the English name where
/// there is no translation. In the order the summary lists them.
///
/// Looked up by name before, on the claim that the seed keeps each name
/// equal to its id; it does not ("Barbell" against "barbell"), so in Arabic
/// every Library row showed English equipment.
List<String> localizedEquipmentNames(
  BuildContext context,
  ExerciseSummary summary,
) =>
    <String>[
      for (int i = 0; i < summary.equipmentNames.length; i++)
        (i < summary.equipmentIds.length
                ? _lookup(context, kEquipmentNamesAr, summary.equipmentIds[i])
                : null) ??
            summary.equipmentNames[i],
    ];

/// Translates an exercise name for a query result that denormalized it
/// (e.g. `StrengthChange.exerciseName`, `LoggedExercise.exerciseName`)
/// rather than joining back to `Exercise` for [ExerciseL10n.displayName].
///
/// [slugsById] is `exerciseSlugsByIdProvider`'s map — built once from the
/// full catalogue rather than adding a slug column to every analytics
/// query that currently only selects a name. Falls back to [fallbackName]
/// when the exercise isn't in the catalogue (a user-created exercise, or
/// the map hasn't loaded yet).
String localizedExerciseName(
  BuildContext context,
  Map<String, String> slugsById,
  String exerciseId,
  String fallbackName,
) {
  final String? slug = slugsById[exerciseId];
  if (slug == null) return fallbackName;
  return _lookup(context, kExerciseNamesAr, slug) ?? fallbackName;
}

/// Arabic instruction steps for all exercises in the bundled catalogue.
const Map<String, List<String>> kExerciseInstructionsAr =
    <String, List<String>>{
  ...kExerciseInstructionsAr1,
  ...kExerciseInstructionsAr2,
  ...kExerciseInstructionsAr3,
  ...kExerciseInstructionsAr4,
  ...kExerciseInstructionsAr5,
  ...kExerciseInstructionsAr6,
  ...kExerciseInstructionsAr7,
  ...kExerciseInstructionsAr8,
  ...kExerciseInstructionsAr9,
  ...kExerciseInstructionsAr10,
};

/// Returns translated instruction steps when the active locale is Arabic.
///
/// A custom exercise—or a future seed row not translated yet—keeps the text
/// stored in the database. A step-count mismatch also falls back as a unit so
/// the UI never combines instructions from different catalogue revisions.
List<String> localizedExerciseInstructions(
  BuildContext context,
  String exerciseSlug,
  List<String> fallback,
) {
  if (Localizations.localeOf(context).languageCode != 'ar') {
    return fallback;
  }
  final List<String>? translated = kExerciseInstructionsAr[exerciseSlug];
  return translated != null && translated.length == fallback.length
      ? translated
      : fallback;
}

/// Fixed vocabularies. Unlike the catalogue tables these are wording rather
/// than data, so they come from the ARB.
extension ExerciseCategoryL10n on ExerciseCategory {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        ExerciseCategory.strength => l10n.categoryStrength,
        ExerciseCategory.cardio => l10n.categoryCardio,
        ExerciseCategory.mobility => l10n.categoryMobility,
        ExerciseCategory.balance => l10n.categoryBalance,
        ExerciseCategory.plyometric => l10n.categoryPlyometric,
        ExerciseCategory.other => l10n.categoryOther,
      };
}

extension DifficultyL10n on Difficulty {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        Difficulty.beginner => l10n.difficultyBeginner,
        Difficulty.intermediate => l10n.difficultyIntermediate,
        Difficulty.advanced => l10n.difficultyAdvanced,
      };
}

extension ForceTypeL10n on ForceType {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        ForceType.push => l10n.forceTypePush,
        ForceType.pull => l10n.forceTypePull,
        ForceType.isometric => l10n.forceTypeIsometric,
      };
}

extension MechanicL10n on Mechanic {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        Mechanic.compound => l10n.mechanicCompound,
        Mechanic.isolation => l10n.mechanicIsolation,
      };
}

extension MovementPatternL10n on MovementPattern {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        MovementPattern.horizontalPush => l10n.patternHorizontalPush,
        MovementPattern.verticalPush => l10n.patternVerticalPush,
        MovementPattern.horizontalPull => l10n.patternHorizontalPull,
        MovementPattern.verticalPull => l10n.patternVerticalPull,
        MovementPattern.kneeDominant => l10n.patternKneeDominant,
        MovementPattern.hipDominant => l10n.patternHipDominant,
        MovementPattern.carry => l10n.patternCarry,
        MovementPattern.rotation => l10n.patternRotation,
        MovementPattern.antiRotation => l10n.patternAntiRotation,
        MovementPattern.other => l10n.patternOther,
      };
}

/// The Arabic name for [key], or null in any other language.
///
/// Only Arabic has a table; every other supported locale is the language the
/// catalogue is already stored in, so there is nothing to look up.
String? _lookup(BuildContext context, Map<String, String> table, String key) {
  if (Localizations.localeOf(context).languageCode != 'ar') {
    return null;
  }
  return table[key];
}

/// The exercises whose shown name, or stored English name, holds every
/// word of [query] (see `matchesSearch`): the Library's search for a query
/// in Arabic, which the SQL search cannot answer because the Arabic names
/// are not in the database.
List<ExerciseSummary> matchingDisplayedName(
  BuildContext context,
  List<ExerciseSummary> exercises,
  String query,
) =>
    <ExerciseSummary>[
      for (final ExerciseSummary s in exercises)
        if (matchesSearch(
          query,
          <String>[s.exercise.displayName(context), s.exercise.name],
        ))
          s,
    ];

/// [exercises] in the order of the name shown: folded the way a search is
/// (see `foldForSearch`), ties broken by the stored name so the order is
/// the same on every build.
///
/// The queries order by the stored English name, so in Arabic the list
/// was in no order a reader could see. Sorted here, not in SQL, because
/// the shown name is a translation the database does not hold; a few
/// hundred names take no time.
List<ExerciseSummary> sortedByDisplayedName(
  BuildContext context,
  List<ExerciseSummary> exercises,
) {
  final List<(ExerciseSummary, String)> keyed = <(ExerciseSummary, String)>[
    for (final ExerciseSummary s in exercises)
      (s, foldForSearch(s.exercise.displayName(context))),
  ];
  keyed.sort(((ExerciseSummary, String) a, (ExerciseSummary, String) b) {
    final int byShown = a.$2.compareTo(b.$2);
    return byShown != 0
        ? byShown
        : a.$1.exercise.name.compareTo(b.$1.exercise.name);
  });
  return <ExerciseSummary>[for (final (ExerciseSummary s, _) in keyed) s];
}
