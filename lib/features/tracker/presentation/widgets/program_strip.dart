/// The Workouts tab's programs: one sideways row of cards.
library;

import 'package:flutter/material.dart';

import '../../../../core/database/daos/program_dao.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../programs/domain/program_catalogue_l10n.dart';

/// Size of one card in [ProgramStrip], before the text scale is applied.
const double _programCardWidth = 168;
const double _programCardHeight = 88;

/// The programs as one row of cards that scrolls sideways.
///
/// They were a column of full-width cards. Three of them, the number the
/// app ships with, took most of the first screen and left the history, the
/// reason this tab is opened, two-thirds of the way down; every program
/// added pushed it further. A row has the same height for three programs or
/// thirty.
class ProgramStrip extends StatelessWidget {
  const ProgramStrip({super.key, required this.programs, required this.onOpen});

  final List<ProgramSummary> programs;
  final ValueChanged<String> onOpen;

  /// The user's own programs first, then the built-in ones, each in the
  /// order of the name shown, ignoring case.
  ///
  /// The query orders by the stored name, byte by byte: the user's
  /// programs fell between the built-in ones, and "Zeta" came before
  /// "alpha". Sorted here, not in SQL, because the shown name can be a
  /// translation the database does not hold.
  static List<ProgramSummary> _ordered(
    List<ProgramSummary> programs,
    String Function(ProgramSummary) nameOf,
  ) {
    final List<(ProgramSummary, String)> named = <(ProgramSummary, String)>[
      for (final ProgramSummary p in programs) (p, nameOf(p).toLowerCase()),
    ];
    named.sort(((ProgramSummary, String) a, (ProgramSummary, String) b) {
      if (a.$1.program.isBuiltIn != b.$1.program.isBuiltIn) {
        return a.$1.program.isBuiltIn ? 1 : -1;
      }
      return a.$2.compareTo(b.$2);
    });
    return <ProgramSummary>[for (final (ProgramSummary p, _) in named) p];
  }

  @override
  Widget build(BuildContext context) {
    final List<ProgramSummary> programs = _ordered(
      this.programs,
      (ProgramSummary p) => p.program.displayName(context),
    );
    // Follows the system text size, so two lines of a name still fit.
    final double cardHeight =
        MediaQuery.textScalerOf(context).scale(_programCardHeight);
    return SizedBox(
      // Room above and below for the card's shadow, which the list clips.
      height: cardHeight + AppSpacing.xs * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The first card lines up with the page; the rest run to the edge
        // of the screen, which is what shows there are more.
        padding: EdgeInsets.symmetric(
          horizontal: context.pageGutter,
          vertical: AppSpacing.xs,
        ),
        itemCount: programs.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final ProgramSummary summary = programs[index];
          return SizedBox(
            width: _programCardWidth,
            child: _ProgramTile(
              name: summary.program.displayName(context),
              dayCount: summary.dayCount,
              onTap: () => onOpen(summary.program.id),
            ),
          );
        },
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.name,
    required this.dayCount,
    required this.onTap,
  });

  final String name;
  final int dayCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: context.l10n.trackerProgramSemantic(
        name,
        context.l10n.dayCount(dayCount),
      ),
      // The name, and how many days it has. The built-in descriptions only
      // repeated the name ("Full Body" over "Full body · 3 days/week"); a
      // program's own description is on its page.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            name,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: <Widget>[
              Icon(
                Icons.event_note_outlined,
                size: AppSpacing.lg,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.dayCount(dayCount),
                  style: AppTypography.caption(theme),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
