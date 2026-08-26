import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/database/tables/muscles.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/filter_chip_group.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../domain/exercise_catalogue_l10n.dart';

/// Placeholder rows shown while the catalogue query resolves.
const int _skeletonRows = 6;

/// Bottom sheet for picking an exercise from the Library.
///
/// Pops with the selected [Exercise], or `null` if dismissed. Reuses the
/// same search/filter data as the Library tab so results stay in sync.
class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedMuscleId;

  /// Committed search term — see [LibraryPage] for why this is held apart
  /// from the controller's text.
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(AppDuration.inputDebounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _commitSearch(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _query;

    final AsyncValue<List<ExerciseSummary>> exercisesAsync = ref.watch(
      searchQuery.isNotEmpty
          ? exercisesSearchStreamProvider(searchQuery)
          : _selectedMuscleId != null
              ? exercisesFilteredStreamProvider(muscleId: _selectedMuscleId)
              : allExercisesStreamProvider,
    );
    final muscles = ref.watch(musclesStreamProvider).value ?? const <Muscle>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              context.l10n.workoutAddExercise,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.l10n.librarySearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: context.l10n.libraryClearSearch,
                        onPressed: () {
                          _searchController.clear();
                          _commitSearch('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
              onSubmitted: _commitSearch,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              // Directional: this pins the filter to the *start* of the
              // sheet, which is the right-hand edge under an RTL locale.
              alignment: AlignmentDirectional.centerStart,
              child: FilterChipGroup<Muscle>(
                label: context.l10n.libraryFilterMuscle,
                value:
                    muscles.where((m) => m.id == _selectedMuscleId).firstOrNull,
                options: muscles,
                getLabel: (m) => m.localizedName(context),
                onChanged: (v) => setState(() => _selectedMuscleId = v?.id),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: exercisesAsync.when(
              data: (exercises) {
                if (exercises.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: context.l10n.libraryNoResults,
                    message: context.l10n.libraryNoResultsMessage,
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final summary = exercises[index];
                    final subtitle = [
                      if (summary.primaryMuscle != null)
                        summary.primaryMuscle!.localizedName(context),
                      if (summary.equipmentNames.isNotEmpty)
                        summary.equipmentNames
                            .map((String e) =>
                                localizedEquipmentName(context, e))
                            .join('، '),
                    ].join(' · ');
                    return ListTile(
                      title: Text(summary.exercise.displayName(context)),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      trailing: Icon(
                        Icons.add_circle_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () => Navigator.of(context).pop(summary.exercise),
                    );
                  },
                );
              },
              loading: () => ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                children: <Widget>[
                  for (int i = 0; i < _skeletonRows; i++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          LoadingShimmer(width: 180, height: 16),
                          SizedBox(height: AppSpacing.sm),
                          LoadingShimmer(width: 120, height: 12),
                        ],
                      ),
                    ),
                ],
              ),
              error: (error, _) => ErrorView(
                title: context.l10n.libraryLoadFailed,
                details: error.toString(),
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
