import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/segmented_pills.dart';
import '../domain/progress_providers.dart';
import 'progress_explainers.dart';
import 'sections/body_section.dart';
import 'sections/habit_sections.dart';
import 'sections/insights_section.dart';
import 'sections/strength_sections.dart';
import 'sections/volume_sections.dart';
import 'widgets/progress_visuals.dart';

/// How far below the top of the scroll view a chapter heading may sit and
/// still count as the chapter being read.
const double _chapterReadLine = AppSpacing.xxxl;

/// The page's chapters, in order. The tab row and the scroll position both
/// speak in these.
enum _Chapter { strength, volume, habits, body }

/// Progress and analytics hub.
///
/// The range control is global and pinned above the scroll view: every
/// chart below answers a question about the same window, so it has to stay
/// in reach from any of them. (It used to scroll away with the first
/// section.) Under it, a row of chapter tabs jumps to a chapter and follows
/// the reader's position, because the page is several screens long.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<_Chapter, GlobalKey> _chapterKeys = <_Chapter, GlobalKey>{
    for (final _Chapter chapter in _Chapter.values) chapter: GlobalKey(),
  };

  /// The chapter being read, or null above the first one.
  ///
  /// This and [_scrolled] are notifiers rather than `setState` fields: they
  /// change while the reader scrolls, and only the pinned tab row and its
  /// hairline show them. As page state, every chapter boundary crossed
  /// rebuilt all thirty sections and every chart, mid-fling.
  final ValueNotifier<_Chapter?> _active = ValueNotifier<_Chapter?>(null);

  /// True while a tab tap is scrolling to its chapter, so the chapters
  /// passed on the way do not each light up in turn. Read only by
  /// [_onScroll], never by `build`, so changing it needs no rebuild.
  bool _jumping = false;

  /// Counts tab taps, so a jump that a later tap has overtaken does not
  /// end the later one's [_jumping] when it finishes.
  int _jump = 0;

  /// Whether anything has scrolled under the pinned controls.
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _active.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// The last chapter whose heading has reached the top of the scroll view.
  _Chapter? _chapterAtTop() {
    final RenderObject? viewport =
        _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return null;
    _Chapter? current;
    for (final _Chapter chapter in _Chapter.values) {
      final RenderObject? heading =
          _chapterKeys[chapter]!.currentContext?.findRenderObject();
      if (heading is! RenderBox || !heading.attached) continue;
      final double top =
          heading.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= _chapterReadLine) current = chapter;
    }
    return current;
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 0 is the page itself; anything deeper is a scrollable inside it.
    if (notification.depth != 0) return false;
    final ScrollMetrics metrics = notification.metrics;
    _Chapter? chapter = _active.value;
    if (!_jumping) {
      chapter = _chapterAtTop();
      // The last chapter can be too short for its heading ever to reach
      // the top, so the end of the page counts as reading it.
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 1) {
        chapter = _Chapter.values.last;
      }
    }
    // A notifier only notifies when its value really changes.
    _active.value = chapter;
    _scrolled.value = metrics.pixels > 0;
    return false;
  }

  Future<void> _jumpTo(_Chapter chapter) async {
    final BuildContext? heading = _chapterKeys[chapter]!.currentContext;
    if (heading == null) return;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final int jump = ++_jump;
    _active.value = chapter;
    _jumping = true;
    await Scrollable.ensureVisible(
      heading,
      duration: reduceMotion ? Duration.zero : AppDuration.slow,
      curve: Curves.easeOutCubic,
    );
    if (mounted && jump == _jump) _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = ref.watch(progressRangeControllerProvider);

    final AppLocalizations l10n = context.l10n;

    // Nothing logged yet: one screen-level invitation instead of a dozen
    // identical "No data yet" cards. Body measurements stay, because they
    // can be recorded before any workout exists.
    //
    // Selected down to the one fact the page needs: the list itself changes
    // with every set logged, and the whole page rebuilt with it.
    final bool nothingLogged = ref.watch(
      loggedExercisesProvider.select(
        (AsyncValue<List<LoggedExercise>> logged) =>
            logged.value?.isEmpty ?? false,
      ),
    );
    if (nothingLogged) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navProgress)),
        body: PageBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmptyState(
                  icon: Icons.insights_outlined,
                  title: l10n.progressEmptyTitle,
                  message: l10n.progressEmptyMessage,
                  actionLabel: l10n.dashboardStartWorkout,
                  onAction: () => context.pushNamed(Routes.activeWorkoutName),
                ),
                const SizedBox(height: AppSpacing.xl),
                BodyMetricsHeader(range: range),
                BodyMetricsSection(range: range),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProgress)),
      body: PageBody(
        // Deliberately not a ListView. A lazy sliver estimates the extent
        // it has not built yet as `remaining children x average height of
        // the built ones`, and this page's children range from a 0px
        // SizedBox.shrink to a ~300px chart card. The average of whichever
        // handful is on screen predicts the rest badly, so maxScrollExtent
        // swung by 3000px as you scrolled; scrolling back up built the
        // short top sections, collapsed the estimate, and the position was
        // clamped against it — a flick upward moved the page *down*, and
        // the top became unreachable by dragging.
        //
        // Building every section up front makes the extent exact instead
        // of estimated. It costs one eager build of ~30 sections, which is
        // what the 8000px-surface test in progress_page_test.dart already
        // exercises. See test/widget/progress_scroll_test.dart.
        child: Column(
          children: <Widget>[
            _RangeSelector(range: range),
            ValueListenableBuilder<_Chapter?>(
              valueListenable: _active,
              builder: (BuildContext context, _Chapter? active, _) =>
                  ProgressChapterTabs<_Chapter>(
                chapters: <(_Chapter, String)>[
                  (_Chapter.strength, l10n.progressChapterStrength),
                  (_Chapter.volume, l10n.progressChapterVolume),
                  (_Chapter.habits, l10n.progressChapterHabits),
                  (_Chapter.body, l10n.progressChapterBody),
                ],
                active: active,
                onSelected: _jumpTo,
              ),
            ),
            // A hairline once content slides under the pinned controls, so
            // they read as a layer above it rather than part of it.
            ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (BuildContext context, bool scrolled, _) => Divider(
                height: 1,
                thickness: 1,
                color: scrolled
                    ? Theme.of(context).colorScheme.outlineVariant
                    : Colors.transparent,
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  key: _viewportKey,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Column(
                    // ListView stretched its children to the full width; Column
                    // centres and shrink-wraps them unless told otherwise.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProgressOverviewHero(range: range),
                      const SizedBox(height: AppSpacing.md),
                      InsightsSection(range: range),

                      // ---- Strength: "am I getting stronger?" ----
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.strength],
                        title: l10n.progressChapterStrength,
                        first: true,
                      ),
                      SectionHeader(
                        title: l10n.progressStrengthChangeTitle,
                        subtitle: l10n.progressStrengthSubtitle(range.name),
                        explainer: ProgressExplainers.strengthChange(l10n),
                      ),
                      StrengthChangeSection(range: range),
                      RelativeStrengthSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: l10n.progressEstimatedOneRmTitle,
                        subtitle: l10n.progressEstimatedOneRmSubtitle,
                        explainer: ProgressExplainers.oneRm(l10n),
                      ),
                      LiftChartSection(range: range),

                      // ---- Volume: "how much work, and where did it go?" ----
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.volume],
                        title: l10n.progressChapterVolume,
                      ),
                      SectionHeader(
                        title: l10n.progressWeeklyVolumeTitle,
                        subtitle: l10n.progressWeeklyVolumeSubtitle(range.name),
                        explainer: ProgressExplainers.volume(l10n),
                      ),
                      VolumeSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                          title: l10n.progressVolumeByMuscleGroupTitle),
                      MuscleGroupSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: l10n.progressTrainingBalanceTitle,
                        explainer: ProgressExplainers.balance(l10n),
                      ),
                      BalanceSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: l10n.progressRepRangeDistributionTitle,
                        explainer: ProgressExplainers.repRange(l10n),
                      ),
                      RepRangeSection(range: range),

                      // ---- Habits: "am I showing up, and how hard?" ----
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.habits],
                        title: l10n.progressChapterHabits,
                      ),
                      SectionHeader(
                        title: l10n.progressConsistencyTitle,
                        explainer: ProgressExplainers.consistency(l10n),
                      ),
                      ConsistencySection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: l10n.progressWorkoutFrequencyTitle),
                      FrequencySection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: l10n.progressTrainingDaysTitle),
                      WeekdaySection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: l10n.progressEffortRecoveryTitle,
                        explainer: ProgressExplainers.rpe(l10n),
                      ),
                      EffortSection(range: range),

                      // ---- Body ----
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.body],
                        title: l10n.progressChapterBody,
                      ),
                      BodyMetricsHeader(range: range),
                      BodyMetricsSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends ConsumerWidget {
  const _RangeSelector({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedPills<ProgressRange>(
      semanticLabel: context.l10n.progressRangeSemantic,
      segments: <PillSegment<ProgressRange>>[
        for (final ProgressRange option in ProgressRange.values)
          PillSegment<ProgressRange>(
            value: option,
            label: context.l10n.progressRangeLabel(option.name),
          ),
      ],
      selected: range,
      onChanged: (ProgressRange selection) =>
          ref.read(progressRangeControllerProvider.notifier).set(selection),
    );
  }
}
