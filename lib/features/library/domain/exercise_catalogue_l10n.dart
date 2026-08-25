import 'package:flutter/widgets.dart';

import '../../../core/database/tables/equipment.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/database/tables/muscles.dart';
import '../../../core/l10n/l10n_extension.dart';
import 'exercise_catalogue_ar.dart';
import 'exercise_instructions_ar_1.dart';
import 'exercise_instructions_ar_2.dart';
import 'exercise_instructions_ar_3.dart';
import 'exercise_instructions_ar_4.dart';

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

/// Translates an equipment name as `ExerciseSummary` carries it.
///
/// That list holds `EquipmentTable.name`, which the seed keeps equal to the
/// row's id — so the same table serves both. Falls back to [name] itself,
/// which is what the English UI already shows.
String localizedEquipmentName(BuildContext context, String name) =>
    _lookup(context, kEquipmentNamesAr, name) ?? name;

/// Arabic instruction steps for all exercises in the bundled catalogue.
const Map<String, List<String>> kExerciseInstructionsAr =
    <String, List<String>>{
  ...kExerciseInstructionsAr1,
  ...kExerciseInstructionsAr2,
  ...kExerciseInstructionsAr3,
  ...kExerciseInstructionsAr4,
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
