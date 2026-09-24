import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/equipment.dart' as db;
import '../../../core/database/tables/exercise_media.dart';
import '../../../core/database/tables/exercise_muscles.dart';
import '../../../core/database/tables/exercises.dart';
import '../../../core/database/tables/muscles.dart';

import '../../../core/formatters/youtube.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../domain/exercise_catalogue_l10n.dart';

/// A curated image wins; a linked video is turned into a thumbnail
/// (already just a picture fallback — see `Youtube.searchUrl` for why a
/// specific video is never treated as "the" demo any more).
String? _pictureUrl(ExerciseMedia? media) {
  if (media == null) return null;
  if (media.type == ExerciseMediaType.video) {
    return Youtube.thumbnailUrl(media.url);
  }
  return media.url ?? media.localAsset;
}

IconData _equipmentIcon(String equipmentId) => switch (equipmentId) {
      'barbell' => Icons.fitness_center,
      'dumbbell' => Icons.sports_gymnastics,
      'machine' => Icons.precision_manufacturing,
      'cable' => Icons.cable,
      'bodyweight' => Icons.accessibility_new,
      'kettlebell' => Icons.sports_kabaddi,
      'band' => Icons.linear_scale,
      'plate' => Icons.circle_outlined,
      'sled' => Icons.directions_run,
      _ => Icons.more_horiz,
    };

/// Library page with search, filters, and exercise list.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedMuscleId;
  String? _selectedEquipmentId;
  MovementPattern? _selectedPattern;

  /// Committed search term. Separate from the controller's text so that
  /// typing does not re-run the query on every keystroke — each one would
  /// otherwise swap the watched provider and start a new database stream.
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Rebuild immediately so the clear affordance tracks the field, but
    // hold the query itself until typing settles.
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
          : (_selectedMuscleId != null ||
                  _selectedEquipmentId != null ||
                  _selectedPattern != null)
              ? exercisesFilteredStreamProvider(
                  muscleId: _selectedMuscleId,
                  equipmentId: _selectedEquipmentId,
                  pattern: _selectedPattern,
                )
              : allExercisesStreamProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.libraryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_off),
            tooltip: context.l10n.libraryClearFilters,
            onPressed: _hasActiveFilters ? _clearFilters : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
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

          // Filter chips
          _buildFilterChips(),

          // Exercise list
          Expanded(
            child: exercisesAsync.when(
              data: (exercises) => _ExerciseList(
                exercises: exercises,
                onExerciseTap: _showExerciseDetail,
                hasActiveFilters: _hasActiveFilters,
                onClearFilters: _clearFilters,
              ),
              loading: () => _buildLoadingGrid(),
              error: (error, _) => ErrorView(
                title: context.l10n.libraryLoadFailed,
                details: error.toString(),
                onRetry: () => ref.invalidate(allExercisesStreamProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _selectedMuscleId != null ||
      _selectedEquipmentId != null ||
      _selectedPattern != null ||
      _query.isNotEmpty;

  void _clearFilters() {
    _debounce?.cancel();
    setState(() {
      _searchController.clear();
      _query = '';
      _selectedMuscleId = null;
      _selectedEquipmentId = null;
      _selectedPattern = null;
    });
  }

  Widget _buildFilterChips() {
    final muscles = ref.watch(musclesStreamProvider).value ?? const <Muscle>[];
    final equipment =
        ref.watch(equipmentStreamProvider).value ?? const <db.Equipment>[];

    // One chip per dimension rather than three inline chip groups. The old
    // layout put a full option list for every dimension in a single
    // horizontal scroller, so the three "All" chips looked identical, the
    // group labels were easy to miss, and the last group's options ran off
    // the edge with nothing to suggest they were there.
    // One left-aligned row that scrolls sideways, like the list below it.
    // A Wrap here was centred by the page's Column and broke onto a second
    // line as soon as a label grew (e.g. "Movement pattern").
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          _FilterMenuChip<Muscle>(
            label: context.l10n.libraryFilterMuscle,
            value: muscles.where((m) => m.id == _selectedMuscleId).firstOrNull,
            options: muscles,
            getLabel: (m) => m.localizedName(context),
            onChanged: (v) => setState(() => _selectedMuscleId = v?.id),
          ),
          _FilterMenuChip<db.Equipment>(
            label: context.l10n.libraryFilterEquipment,
            value: equipment
                .where((e) => e.id == _selectedEquipmentId)
                .firstOrNull,
            options: equipment,
            getLabel: (e) => e.name,
            onChanged: (v) => setState(() => _selectedEquipmentId = v?.id),
          ),
          _FilterMenuChip<MovementPattern>(
            label: context.l10n.libraryFilterPattern,
            value: _selectedPattern,
            options: MovementPattern.values,
            getLabel: (p) => p.localizedLabel(context.l10n),
            onChanged: (v) => setState(() => _selectedPattern = v),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingGrid() {
    // Placeholders take the shape of what replaces them, so the page does
    // not jump when the catalogue arrives: rows on phones, cards on wider
    // screens (see `_ExerciseList`).
    if (context.breakpoint == Breakpoint.compact) {
      return ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        itemCount: 8,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, __) => const _ExerciseRowSkeleton(),
      );
    }
    final columns = context.gridColumns;
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => _ExerciseCardSkeleton(),
    );
  }

  void _showExerciseDetail(ExerciseSummary summary) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExerciseDetailSheet(exerciseId: summary.exercise.id),
    );
  }
}

/// A single filter dimension, collapsed to one chip that opens its options.
///
/// Shows the dimension name when unset and the chosen value when set, so
/// the active filters are readable at a glance without a legend.
class _FilterMenuChip<T extends Object> extends StatelessWidget {
  const _FilterMenuChip({
    required this.label,
    required this.value,
    required this.options,
    required this.getLabel,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) getLabel;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool active = value != null;

    return PopupMenuButton<T?>(
      tooltip: context.l10n.libraryFilterBy(label.toLowerCase()),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => <PopupMenuEntry<T?>>[
        PopupMenuItem<T?>(
          value: null,
          child: Text(context.l10n.libraryFilterAllOf(label)),
        ),
        const PopupMenuDivider(),
        for (final T option in options)
          PopupMenuItem<T?>(value: option, child: Text(getLabel(option))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: const BoxConstraints(
          minHeight: AppSpacing.minTapTarget,
        ),
        decoration: BoxDecoration(
          color: active ? scheme.secondaryContainer : scheme.surface,
          border: Border.all(
            color: active ? scheme.secondary : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              active ? getLabel(value as T) : label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: active
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              active ? Icons.close : Icons.arrow_drop_down,
              size: 18,
              color: active
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Aspect ratio of a grid card: portrait, to fit a 16:9 thumbnail plus
/// three lines of metadata without clipping.
const double _cardAspectRatio = 0.75;

/// Exercise results.
///
/// A phone gets a dense list rather than a one-column grid: at the card
/// aspect ratio above, a single column shows barely one and a half
/// exercises per screen, which makes browsing a 400-entry catalogue
/// unusable. Wider layouts have the room for the richer card, so they keep
/// the grid.
class _ExerciseList extends StatelessWidget {
  const _ExerciseList({
    required this.exercises,
    required this.onExerciseTap,
    required this.hasActiveFilters,
    required this.onClearFilters,
  });

  final List<ExerciseSummary> exercises;
  final void Function(ExerciseSummary) onExerciseTap;
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: context.l10n.libraryNoResults,
        message: context.l10n.libraryNoResultsMessage,
        actionLabel: hasActiveFilters ? context.l10n.libraryClearFilters : null,
        onAction: hasActiveFilters ? onClearFilters : null,
      );
    }

    final ThemeData theme = Theme.of(context);
    final bool compact = context.breakpoint == Breakpoint.compact;

    final Widget countLabel = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        context.l10n.exerciseCount(exercises.length),
        style: AppTypography.eyebrow(theme),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        countLabel,
        Expanded(
          child: compact
              ? ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: exercises.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _ExerciseRow(
                    summary: exercises[index],
                    onTap: () => onExerciseTap(exercises[index]),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: context.gridColumns,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: _cardAspectRatio,
                  ),
                  itemCount: exercises.length,
                  itemBuilder: (context, index) => _ExerciseCard(
                    summary: exercises[index],
                    onTap: () => onExerciseTap(exercises[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Dense one-line-per-exercise row used on phones.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.summary, required this.onTap});

  final ExerciseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final exercise = summary.exercise;
    final String equipmentLabel = summary.equipmentNames
        .map((String e) => localizedEquipmentName(context, e))
        .join('، ');
    final String? muscle = summary.primaryMuscle?.localizedName(context);
    final String? thumbnailUrl = _pictureUrl(summary.media);
    final IconData fallbackIcon = summary.equipmentNames.isEmpty
        ? Icons.fitness_center
        : _equipmentIcon(summary.equipmentNames.first);

    final String meta = <String>[
      if (muscle != null) muscle,
      if (equipmentLabel.isNotEmpty) equipmentLabel,
      exercise.movementPattern.localizedLabel(context.l10n),
    ].join(' · ');

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel: '${exercise.displayName(context)}, $meta',
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: _rowThumbnailSize,
              height: _rowThumbnailSize,
              child: thumbnailUrl == null
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        fallbackIcon,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : _ExerciseThumbnail(
                      url: thumbnailUrl,
                      fallbackUrl: _pictureUrl(summary.fallbackMedia),
                      fallbackIcon: fallbackIcon,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  exercise.displayName(context),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  meta,
                  style: AppTypography.caption(theme),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (exercise.isBodyweight) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.accessibility_new,
              size: 16,
              color: scheme.primary,
              semanticLabel: context.l10n.libraryBodyweight,
            ),
          ],
        ],
      ),
    );
  }
}

/// Square thumbnail edge for the compact row.
const double _rowThumbnailSize = 56;

/// Individual exercise card.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.summary, required this.onTap});

  final ExerciseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final exercise = summary.exercise;
    final equipmentLabel = summary.equipmentNames
        .map((String e) => localizedEquipmentName(context, e))
        .join('، ');

    return AppCard(
      onTap: onTap,
      semanticLabel: '${exercise.displayName(context)}, '
          '${summary.primaryMuscle?.localizedName(context) ?? ''}, '
          '$equipmentLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pictureUrl(summary.media) case final url?) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _ExerciseThumbnail(
                  url: url,
                  fallbackUrl: _pictureUrl(summary.fallbackMedia),
                  fallbackIcon: summary.equipmentNames.isEmpty
                      ? Icons.fitness_center
                      : _equipmentIcon(summary.equipmentNames.first),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // Muscle group badge
          if (summary.primaryMuscle case final muscle?)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                muscle.localizedName(context),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          // Name
          Text(
            exercise.displayName(context),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          // Equipment + pattern
          if (equipmentLabel.isNotEmpty)
            Row(
              children: [
                Icon(
                  _equipmentIcon(summary.equipmentNames.first),
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    equipmentLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  exercise.movementPattern.localizedLabel(context.l10n),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Bodyweight indicator
          if (exercise.isBodyweight)
            Row(
              children: [
                Icon(Icons.accessibility_new, size: 14, color: scheme.primary),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  context.l10n.libraryBodyweight,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Skeleton for [_ExerciseRow]: same padding, thumbnail and two text lines.
class _ExerciseRowSkeleton extends StatelessWidget {
  const _ExerciseRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: <Widget>[
          LoadingShimmer(
            width: _rowThumbnailSize,
            height: _rowThumbnailSize,
            radius: AppRadius.sm,
          ),
          SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LoadingShimmer(width: 160, height: 14),
              SizedBox(height: AppSpacing.sm),
              LoadingShimmer(width: 110, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader for exercise card.
class _ExerciseCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingShimmer(width: 80, height: 20, radius: AppRadius.pill),
          SizedBox(height: AppSpacing.sm),
          LoadingShimmer(width: double.infinity, height: 20),
          SizedBox(height: AppSpacing.xs),
          LoadingShimmer(width: 100, height: 14),
          SizedBox(height: AppSpacing.xxs),
          LoadingShimmer(width: 120, height: 14),
          Spacer(),
        ],
      ),
    );
  }
}

/// Exercise detail bottom sheet — loads the fully assembled
/// [ExerciseDetail] (muscles by role, equipment, ordered steps, media,
/// tags) for one exercise.
class _ExerciseDetailSheet extends ConsumerWidget {
  const _ExerciseDetailSheet({required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(exerciseDetailProvider(exerciseId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: detailAsync.when(
          data: (detail) => detail == null
              ? EmptyState(
                  icon: Icons.search_off,
                  title: context.l10n.libraryExerciseNotFound,
                )
              : _ExerciseDetailBody(
                  detail: detail,
                  scrollController: scrollController,
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(
            title: context.l10n.libraryLoadFailed,
            details: error.toString(),
            onRetry: () => ref.invalidate(exerciseDetailProvider(exerciseId)),
          ),
        ),
      ),
    );
  }
}

class _ExerciseDetailBody extends StatelessWidget {
  const _ExerciseDetailBody({
    required this.detail,
    required this.scrollController,
  });

  final ExerciseDetail detail;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final exercise = detail.exercise;
    final primary = detail.muscles
        .where((m) => m.role == MuscleRole.primary)
        .map((m) => m.muscle);
    final secondary = detail.muscles
        .where((m) => m.role != MuscleRole.primary)
        .map((m) => m.muscle);
    final picture = _pictureUrl(bestMedia(detail.media));
    final fallbackIcon = detail.equipment.isEmpty
        ? Icons.fitness_center
        : _equipmentIcon(detail.equipment.first.equipment.id);
    final List<String> instructions = localizedExerciseInstructions(
      context,
      exercise.slug,
      detail.instructions.map((step) => step.instruction).toList(),
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SheetHandle(),
        const SizedBox(height: AppSpacing.lg),

        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Semantics(
              button: true,
              label: context.l10n.librarySearchYoutube(
                exercise.displayName(context),
              ),
              child: GestureDetector(
                onTap: () => _searchOnYoutube(context, exercise.name),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (picture != null)
                      _ExerciseThumbnail(
                        url: picture,
                        fallbackUrl: _pictureUrl(
                          detail.media.firstWhereOrNull(
                            (media) => media.type == ExerciseMediaType.video,
                          ),
                        ),
                        fallbackIcon: fallbackIcon,
                      )
                    else
                      Container(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            fallbackIcon,
                            color: scheme.onSurfaceVariant,
                            size: 28,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Name
        Text(
          exercise.displayName(context),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Metadata chips
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final muscle in primary)
              _MetadataChip(
                icon: Icons.fitness_center,
                label: muscle.localizedName(context),
                color: scheme.primary,
              ),
            if (secondary.isNotEmpty)
              _MetadataChip(
                icon: Icons.fitness_center_outlined,
                label:
                    secondary.map((m) => m.localizedName(context)).join('، '),
                color: scheme.secondary,
              ),
            for (final link in detail.equipment)
              _MetadataChip(
                icon: _equipmentIcon(link.equipment.id),
                label: link.equipment.localizedName(context),
                color: scheme.tertiary,
              ),
            _MetadataChip(
              icon: Icons.swap_horiz,
              label: exercise.movementPattern.localizedLabel(context.l10n),
              color: scheme.outline,
            ),
            if (exercise.isBodyweight)
              _MetadataChip(
                icon: Icons.accessibility_new,
                label: context.l10n.libraryBodyweight,
                color: scheme.primary,
              ),
            for (final tag in detail.tags)
              _MetadataChip(
                icon: Icons.label_outline,
                label: tag,
                color: scheme.outlineVariant,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // Instructions
        Text(
          context.l10n.libraryInstructions,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < instructions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    instructions[i],
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),

        Text(
          context.l10n.libraryVideoDemo,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => _searchOnYoutube(context, exercise.name),
          icon: const Icon(Icons.search),
          label: Text(context.l10n.librarySearchOnYoutube),
        ),
        const SizedBox(height: AppSpacing.xxxl),
      ],
    );
  }

  /// Opens a YouTube search for [exerciseName].
  ///
  /// Callers pass the English `exercise.name`, not the localized one, even
  /// in Arabic: form demonstrations for these movements are overwhelmingly
  /// indexed under their English names, and searching the Arabic name
  /// returns far less.
  Future<void> _searchOnYoutube(
    BuildContext context,
    String exerciseName,
  ) async {
    final launched = await launchUrl(
      Youtube.searchUrl(exerciseName),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryYoutubeOpenFailed)),
      );
    }
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ThumbState { loading, available, unavailable }

/// Exercise thumbnail with loading and error states.
///
/// YouTube doesn't 404 a `hqdefault.jpg` request for a video that's been
/// removed, made private, or never existed — it returns a 200 with a
/// fixed 120×90 grey placeholder instead. `errorBuilder` never fires for
/// that case, so it has to be detected by its distinctive size and treated
/// the same as a load failure: fall back to an icon, not a blurry grey box.
class _ExerciseThumbnail extends StatefulWidget {
  const _ExerciseThumbnail({
    required this.url,
    required this.fallbackIcon,
    this.fallbackUrl,
  });

  final String url;
  final String? fallbackUrl;
  final IconData fallbackIcon;

  @override
  State<_ExerciseThumbnail> createState() => _ExerciseThumbnailState();
}

class _ExerciseThumbnailState extends State<_ExerciseThumbnail> {
  static const int _placeholderWidth = 120;
  static const int _placeholderHeight = 90;

  late ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  _ThumbState _state = _ThumbState.loading;
  bool _usingFallback = false;

  ImageProvider _providerFor(String source) {
    final uri = Uri.tryParse(source);
    final isRemote =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    return isRemote ? NetworkImage(source) : AssetImage(source);
  }

  void _listenToProvider(String source) {
    _provider = _providerFor(source);
    _listener = ImageStreamListener(_onImage, onError: _onError);
    _stream = _provider.resolve(const ImageConfiguration())
      ..addListener(_listener!);
  }

  @override
  void initState() {
    super.initState();
    _listenToProvider(widget.url);
  }

  @override
  void didUpdateWidget(covariant _ExerciseThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.fallbackUrl == widget.fallbackUrl) {
      return;
    }

    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _state = _ThumbState.loading;
    _usingFallback = false;
    _listenToProvider(widget.url);
  }

  void _tryFallback() {
    final fallbackUrl = widget.fallbackUrl;
    if (_usingFallback || fallbackUrl == null || fallbackUrl == widget.url) {
      if (mounted) setState(() => _state = _ThumbState.unavailable);
      return;
    }

    _usingFallback = true;
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    if (mounted) setState(() => _state = _ThumbState.loading);
    _listenToProvider(fallbackUrl);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final bool isMissingThumbnail = info.image.width == _placeholderWidth &&
        info.image.height == _placeholderHeight;
    if (isMissingThumbnail) {
      _tryFallback();
      return;
    }
    if (!mounted) return;
    setState(() => _state = _ThumbState.available);
  }

  void _onError(Object error, StackTrace? stackTrace) {
    _tryFallback();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: switch (_state) {
        _ThumbState.loading => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _ThumbState.unavailable => Center(
            child: Icon(
              widget.fallbackIcon,
              color: scheme.onSurfaceVariant,
              size: 28,
            ),
          ),
        _ThumbState.available => Image(
            image: _provider,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
      },
    );
  }
}
