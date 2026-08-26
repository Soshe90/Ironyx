import 'package:flutter/widgets.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/database/tables/programs.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../library/domain/exercise_catalogue_ar.dart';
import 'program_catalogue_ar.dart';

/// Localized display copy for a built-in program row.
///
/// Mirrors `ExerciseL10n` in `exercise_catalogue_l10n.dart`: translate at
/// the point of display, never the stored row, so a re-seed can't clobber
/// a translation and a user's own program keeps the words they typed.
extension ProgramL10n on Program {
  String displayName(BuildContext context) =>
      _lookup(context, kProgramNamesAr, id) ?? name;

  /// The seeded description ("Full body · 3 days/week") re-composed from
  /// [splitType] and [dayCount] through the ARB, rather than translating
  /// the stored sentence directly — the DB only holds the English one.
  ///
  /// Falls back to the stored [description] for anything outside the three
  /// built-in split types: a custom program's description is freeform user
  /// text with no split type to recompose from, and translating it would
  /// show the user words they never wrote.
  String? localizedDescription(BuildContext context, int dayCount) {
    if (Localizations.localeOf(context).languageCode != 'ar') {
      return description;
    }
    final AppLocalizations l10n = context.l10n;
    final String? splitLabel = switch (splitType) {
      'fullBody' => l10n.programSplitFullBody,
      'upperLower' => l10n.programSplitUpperLower,
      'ppl' => l10n.programSplitPpl,
      _ => null,
    };
    if (splitLabel == null) return description;
    return '$splitLabel · ${l10n.programWeeklyFrequency(dayCount)}';
  }
}

/// Localized display copy for one day within a built-in program.
extension ProgramDayL10n on ProgramDay {
  String displayDayName(BuildContext context) =>
      _lookup(context, kProgramDayNamesAr, templateId) ?? dayName;
}

/// Localized display copy for one exercise row within a program day.
///
/// Reuses the exercise catalogue's own translation table — a program's
/// exercises are catalogue exercises, the same ones the library page shows,
/// so they carry the same Arabic names rather than a program-specific copy.
extension ProgramDayExerciseL10n on ProgramDayExercise {
  String displayName(BuildContext context) =>
      _lookup(context, kExerciseNamesAr, exerciseSlug) ?? exerciseName;
}

/// The Arabic name for [key], or null in any other language.
String? _lookup(BuildContext context, Map<String, String> table, String key) {
  if (Localizations.localeOf(context).languageCode != 'ar') {
    return null;
  }
  return table[key];
}
