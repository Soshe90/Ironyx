/// The exercise search shared by the Library page and the exercise picker
/// sheet: the search box's state, which query answers it, what is shown,
/// and the line under an exercise's name.
///
/// Both screens carried their own copy of all of this, and every fix had
/// to be made twice (the search that dropped the filters, the Arabic
/// search, the order, the Retry).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/formatters/search_fold.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/exercise_catalogue_l10n.dart';

/// A search box whose committed [query] waits until typing settles.
///
/// The query is held apart from the controller's text so that typing does
/// not re-run the search on every keystroke: each one would swap the
/// watched provider and start a new database stream.
mixin DebouncedSearch<T extends StatefulWidget> on State<T> {
  final TextEditingController searchController = TextEditingController();

  /// The search in force, trimmed.
  String query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  /// For `onChanged`. Rebuilds at once, so a clear button can follow the
  /// field, and commits the query once typing pauses.
  void onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(AppDuration.inputDebounce, () {
      if (mounted) setState(() => query = value.trim());
    });
  }

  /// For `onSubmitted` and a clear button: commits [value] now.
  void commitSearch(String value) {
    _debounce?.cancel();
    setState(() => query = value.trim());
  }

  /// Empties the field and the query, without a rebuild of its own (for a
  /// caller resetting other state in the same `setState`).
  void resetSearch() {
    _debounce?.cancel();
    searchController.clear();
    query = '';
  }
}

/// The query that answers [query] and the filters: one query for all of
/// them together (see `ExerciseDao.filterBy`), or the whole catalogue when
/// there is nothing to narrow by.
///
/// An Arabic [query] is not part of it. The database holds only the
/// English names, so an Arabic search is matched in memory, by
/// [shownExercises], over the list this gives.
ProviderBase<AsyncValue<List<ExerciseSummary>>> exerciseSource({
  required String query,
  String? muscleId,
  String? equipmentId,
  MovementPattern? pattern,
}) {
  final String? sqlQuery =
      query.isNotEmpty && !containsArabic(query) ? query : null;
  final bool narrowed = sqlQuery != null ||
      muscleId != null ||
      equipmentId != null ||
      pattern != null;
  return narrowed
      ? exercisesFilteredStreamProvider(
          query: sqlQuery,
          muscleId: muscleId,
          equipmentId: equipmentId,
          pattern: pattern,
        )
      : allExercisesStreamProvider;
}

/// What is listed for [query] out of [exercises] (from [exerciseSource]):
/// the Arabic match applied when the query is Arabic, then in the order of
/// the names shown.
List<ExerciseSummary> shownExercises(
  BuildContext context,
  List<ExerciseSummary> exercises,
  String query,
) =>
    sortedByDisplayedName(
      context,
      containsArabic(query)
          ? matchingDisplayedName(context, exercises, query)
          : exercises,
    );

/// The line under an exercise's name: primary muscle, equipment and, with
/// [withPattern], movement pattern, each translated, "·" between them.
String exerciseDetailLine(
  BuildContext context,
  ExerciseSummary summary, {
  bool withPattern = true,
}) {
  final String equipment = localizedEquipmentNames(context, summary)
      .join(context.l10n.listSeparator);
  return <String>[
    if (summary.primaryMuscle case final muscle?) muscle.localizedName(context),
    if (equipment.isNotEmpty) equipment,
    if (withPattern)
      summary.exercise.movementPattern.localizedLabel(context.l10n),
  ].join(' · ');
}
