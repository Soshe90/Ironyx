import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/clock.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/responsive.dart';
import 'sections/progress_section.dart';
import 'sections/recent_section.dart';
import 'sections/today_card.dart';
import 'sections/week_section.dart';

/// Central hub. Branch index 0 and the app's start destination.
///
/// Laid out in descending priority rather than as a uniform grid: the
/// primary action first, this week's training status second, progress
/// signals third, recent activity last. Cards still own their own async
/// state, so one failing query degrades a single block instead of the page.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _Greeting(),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.navSettings,
            onPressed: () => context.pushNamed(Routes.settingsName),
          ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          gutter: false,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: context.sliverGutter.copyWith(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.xl,
                ),
                sliver: SliverToBoxAdapter(
                  child: context.isAtLeast(Breakpoint.expanded)
                      ? const _DesktopPrimaryRow()
                      : const TodayCard(),
                ),
              ),
              if (!context.isAtLeast(Breakpoint.expanded))
                SliverPadding(
                  padding: context.sliverGutter,
                  sliver: const SliverToBoxAdapter(child: ThisWeekSection()),
                ),
              if (context.isAtLeast(Breakpoint.expanded))
                SliverPadding(
                  padding: context.sliverGutter.copyWith(
                    top: AppSpacing.xl,
                    bottom: AppSpacing.xl,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: _DesktopSecondaryRow(),
                  ),
                )
              else ...<Widget>[
                SliverPadding(
                  padding: context.sliverGutter.copyWith(top: AppSpacing.xl),
                  sliver: const SliverToBoxAdapter(child: ProgressSection()),
                ),
                SliverPadding(
                  padding: context.sliverGutter.copyWith(
                    top: AppSpacing.xl,
                    bottom: AppSpacing.xl,
                  ),
                  sliver: const SliverToBoxAdapter(child: RecentSection()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// The desktop rows use `start` alignment, not `stretch`: a sliver hands its
// child an unbounded height, and a stretched Row demands a finite one.
class _DesktopPrimaryRow extends StatelessWidget {
  const _DesktopPrimaryRow();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 2, child: TodayCard()),
          SizedBox(width: AppSpacing.lg),
          Expanded(child: ThisWeekSection()),
        ],
      );
}

class _DesktopSecondaryRow extends StatelessWidget {
  const _DesktopSecondaryRow();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 2, child: ProgressSection()),
          SizedBox(width: AppSpacing.lg),
          Expanded(child: RecentSection()),
        ],
      );
}

/// Time-of-day greeting. Orients the user faster than a static wordmark,
/// which they already know — they just opened the app.
///
/// Watches [localNowProvider] rather than reading the clock in `build()`,
/// so it changes at noon and 18:00 and after a resume, not only when
/// something else happens to rebuild the app bar.
class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DayPart part = ref.watch(localNowProvider.select(DayPart.of));
    final AppLocalizations l10n = context.l10n;
    final String greeting = switch (part) {
      DayPart.morning => l10n.greetingMorning,
      DayPart.afternoon => l10n.greetingAfternoon,
      DayPart.evening => l10n.greetingEvening,
    };
    return Text(greeting);
  }
}
