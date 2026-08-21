import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/database/tables/muscles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/filter_chip_group.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text;

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
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Add exercise',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () => setState(_searchController.clear),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChipGroup<Muscle>(
                label: 'Muscle',
                value:
                    muscles.where((m) => m.id == _selectedMuscleId).firstOrNull,
                options: muscles,
                getLabel: (m) => m.displayName,
                onChanged: (v) => setState(() => _selectedMuscleId = v?.id),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: exercisesAsync.when(
              data: (exercises) {
                if (exercises.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    title: 'No exercises found',
                    message: 'Try adjusting your search or filter.',
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
                        summary.primaryMuscle!.displayName,
                      if (summary.equipmentNames.isNotEmpty)
                        summary.equipmentNames.join(', '),
                    ].join(' · ');
                    return ListTile(
                      title: Text(summary.exercise.name),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      onTap: () => Navigator.of(context).pop(summary.exercise),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(
                title: 'Failed to load exercises',
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
