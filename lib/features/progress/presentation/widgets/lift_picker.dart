import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/sheet_handle.dart';

/// Past this many logged lifts the picker offers a search box. Below it the
/// whole list fits on the sheet, and a search box would only be clutter
/// (and, focused, a keyboard over the list).
const int liftPickerSearchFrom = 8;

/// One lift the picker can offer.
class LiftOption {
  const LiftOption({
    required this.id,
    required this.name,
    required this.storedName,
    required this.sessions,
  });

  final String id;

  /// The name in the user's language, as shown.
  final String name;

  /// The stored (English) name, also searched, so "bench" finds the lift
  /// while the app is in Arabic.
  final String storedName;

  /// "24 sessions", already localized.
  final String sessions;
}

/// [text] reduced to what a search should compare: lower case, and for
/// Arabic without diacritics or tatweel, with the alef, yeh, waw and teh
/// marbuta variants a keyboard may or may not produce folded together.
String foldForSearch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '')
    .replaceAll(RegExp('[آأإٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ئ', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ة', 'ه');

/// Whether every word of [query] appears in one of [names], after
/// [foldForSearch]. Words may come in any order ("bench barbell" finds
/// "Barbell Bench Press"); an empty query matches everything.
bool liftMatchesQuery(String query, Iterable<String> names) {
  final List<String> words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final List<String> folded = <String>[for (final n in names) foldForSearch(n)];
  return folded.any((String name) => words.every(name.contains));
}

/// The lift field on the lift chart's card. Looks like the form field it
/// replaces; tapping it opens [showLiftPicker].
class LiftPickerField extends StatelessWidget {
  const LiftPickerField({
    required this.selectedId,
    required this.label,
    required this.onTap,
    super.key,
  });

  /// The lift shown, so a test (or a caller) can read the selection.
  final String selectedId;

  /// The chosen lift with its session count, already localized.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String field = context.l10n.progressExerciseField;
    return Semantics(
      button: true,
      label: '$field: $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: field,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Lets the user choose one of [options] (logged lifts, most-trained
/// first). Resolves to the chosen id, or null if dismissed.
///
/// Replaced a dropdown of every logged lift, which had no search and ran
/// several screens long for someone training forty lifts. Only logged
/// lifts are offered: the Library picker searches the whole catalogue,
/// and a lift never trained has nothing to chart.
Future<String?> showLiftPicker(
  BuildContext context, {
  required List<LiftOption> options,
  required String? selectedId,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (BuildContext context) =>
          LiftPickerSheet(options: options, selectedId: selectedId),
    );

class LiftPickerSheet extends StatefulWidget {
  const LiftPickerSheet({
    required this.options,
    required this.selectedId,
    super.key,
  });

  final List<LiftOption> options;
  final String? selectedId;

  @override
  State<LiftPickerSheet> createState() => _LiftPickerSheetState();
}

class _LiftPickerSheetState extends State<LiftPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool searchable = widget.options.length > liftPickerSearchFrom;
    // Filtered in memory: a few hundred lifts at most, and the shown name
    // is a translation the database does not hold.
    final List<LiftOption> shown = <LiftOption>[
      for (final LiftOption o in widget.options)
        if (liftMatchesQuery(_search.text, <String>[o.name, o.storedName])) o,
    ];

    final Widget title = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        context.l10n.progressChooseLift,
        style: theme.textTheme.titleLarge,
      ),
    );

    Widget list(ScrollController? scroll, {required bool shrinkWrap}) =>
        shown.isEmpty
            ? EmptyState(
                icon: Icons.search_off,
                title: context.l10n.progressNoLiftMatches,
                message: context.l10n.progressNoLiftMatchesMessage,
              )
            : ListView.builder(
                controller: scroll,
                shrinkWrap: shrinkWrap,
                itemCount: shown.length,
                itemBuilder: (BuildContext context, int i) =>
                    _row(context, shown[i]),
              );

    if (!searchable) {
      // A short list cannot change length, so the sheet is as tall as its
      // rows. At a fixed share of the screen, one lift sat at the top of a
      // mostly empty sheet (seen on the phone).
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SheetHandle(),
            title,
            Flexible(child: list(null, shrinkWrap: true)),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => Padding(
        // Keeps the list above the keyboard while searching.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SheetHandle(),
            title,
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.l10n.progressSearchLifts,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: context.l10n.libraryClearSearch,
                          onPressed: () => setState(_search.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(child: list(scroll, shrinkWrap: false)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, LiftOption o) {
    final ThemeData theme = Theme.of(context);
    final bool chosen = o.id == widget.selectedId;
    return ListTile(
      selected: chosen,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(
        Icons.check,
        color: chosen ? theme.colorScheme.primary : Colors.transparent,
      ),
      title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(o.sessions, style: theme.textTheme.bodySmall),
      onTap: () => Navigator.of(context).pop(o.id),
    );
  }
}
