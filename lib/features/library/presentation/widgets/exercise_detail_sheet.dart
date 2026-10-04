import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/daos/exercise_dao.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/database/tables/exercise_media.dart';
import '../../../../core/database/tables/exercise_muscles.dart';
import '../../../../core/formatters/youtube.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/sheet_handle.dart';
import '../../domain/exercise_catalogue_l10n.dart';
import 'exercise_media.dart';

/// Opens the "how to do it" sheet for [exerciseId]: media, muscles,
/// equipment and the ordered steps.
///
/// The one entry point every screen that lists exercises uses (Library,
/// a program's days, a saved workout, the live session), so they all show
/// the same sheet. An id that no longer resolves — a deleted custom
/// exercise referenced by an old workout — gets the sheet's not-found
/// state, not an error.
Future<void> showExerciseDetailSheet(BuildContext context, String exerciseId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ExerciseDetailSheet(exerciseId: exerciseId),
  );
}

/// Makes an exercise's heading open its how-to sheet.
///
/// Shared by every list that names an exercise outside the Library (a
/// program day, a saved workout, the live session) so the target size,
/// ripple and screen-reader treatment are identical everywhere. Put an
/// [ExerciseInfoIcon] inside [child]: it is both the visible cue and, via
/// its semantic label, what the merged button announces as its purpose.
class ExerciseInfoTapTarget extends StatelessWidget {
  const ExerciseInfoTapTarget({
    required this.exerciseId,
    required this.child,
    super.key,
  });

  final String exerciseId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: () => showExerciseDetailSheet(context, exerciseId),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The small "ⓘ" beside an exercise name that marks it as tappable for
/// instructions. See [ExerciseInfoTapTarget].
class ExerciseInfoIcon extends StatelessWidget {
  const ExerciseInfoIcon({required this.exerciseName, super.key});

  /// Localized display name, used in the screen-reader label.
  final String exerciseName;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.info_outline,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      semanticLabel: context.l10n.libraryHowToPerform(exerciseName),
    );
  }
}

/// Exercise detail bottom sheet — loads the fully assembled
/// [ExerciseDetail] (muscles by role, equipment, ordered steps, media,
/// tags) for one exercise.
class ExerciseDetailSheet extends ConsumerWidget {
  const ExerciseDetailSheet({required this.exerciseId, super.key});

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
    final picture = exercisePictureUrl(bestMedia(detail.media));
    final fallbackIcon = detail.equipment.isEmpty
        ? Icons.fitness_center
        : equipmentIcon(detail.equipment.first.equipment.id);
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
                      ExerciseThumbnail(
                        url: picture,
                        fallbackUrl: exercisePictureUrl(
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
                label: secondary
                    .map((m) => m.localizedName(context))
                    .join(context.l10n.listSeparator),
                color: scheme.secondary,
              ),
            for (final link in detail.equipment)
              _MetadataChip(
                icon: equipmentIcon(link.equipment.id),
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
