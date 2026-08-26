# Widget reference

What every shared widget in the app is for, and when to reach for it.

Two layers:

- **`lib/core/widgets/`** — the design system. Feature-agnostic and reusable
  anywhere. Nothing here may import from `lib/features/`.
- **`lib/features/*/presentation/widgets/`** — feature widgets. Free to read
  providers and the database; scoped to one feature.

---

## Core — layout and structure

| Widget | Purpose |
| --- | --- |
| `PageBody` (`page_body.dart`) | Centres page content, caps its max width, applies the responsive gutter. Wrap the scroll view rather than each child so the scrollbar sits at the true screen edge on desktop. |
| `AppCard` (`app_card.dart`) | The standard surface for grouped content. Tappable variants get an ink ripple and a semantics label so a screen reader announces the card as a single button. |
| `SectionHeader` (`section_header.dart`) | Titles a group of content, with an optional trailing action and an optional info affordance. Gives the app one vertical rhythm for section breaks. |
| `StickyActionBar` (`sticky_action_bar.dart`) | Pins a screen's primary commit action (finish, save) above the fold instead of leaving it at the bottom of a list that grows as you add exercises. |
| `SheetHandle` (`sheet_handle.dart`) | The grab handle at the top of a bottom sheet. Decorative — excluded from semantics so the sheet's heading is what gets announced. |
| `Breakpoint`, `BreakpointContext` (`responsive.dart`) | Layout breakpoints (`compact` / `medium` / `expanded`) plus `context.breakpoint` and `context.contentMaxWidth`. Verified at 360 dp, 768 dp and 1440 dp. |

## Core — metrics and data display

| Widget | Purpose |
| --- | --- |
| `MetricBlock` (`metric_block.dart`) | Eyebrow label, large tabular number, caption, optional trend — the shape every fitness metric in this app takes. Deliberately *not* a card, so screens can render it straight onto a surface without nesting cards to show a number. |
| `StatStrip`, `Stat` (`stat_strip.dart`) | A row of small stats separated by hairline rules ("volume / sets / duration"). Wraps to a second line rather than shrinking text below legibility. At most one `Stat` per strip sets `emphasis`. |
| `TrendBadge`, `TrendDirection` (`trend_badge.dart`) | Small coloured pill with a direction arrow for "up / down / flat vs. last period". The enum is domain-neutral on purpose — features map their own trend types at the presentation boundary, which is what keeps `core/` free of feature imports. |
| `PrBadge` (`pr_badge.dart`) | Marks a workout that set a new estimated-1RM personal record. Uses the dedicated `AppColors.personalRecord` accent so a PR reads identically everywhere and never collides with the primary action colour. |
| `Sparkline` (`sparkline.dart`) | A minimal, axis-free trend line for embedding in a card. Not a chart — use `fl_chart` directly when you need axes, tooltips or touch. |
| `MetricExplainer`, `MetricInfoButton`, `showMetricExplainer` (`metric_explainer.dart`) | The "what does this number mean?" sheet: plain-language summary, the formula rendered as an illustration, a worked example with real numbers, how-to-read bullets, and a caveat. Attach one to any metric whose name is jargon. |

## Core — state handling

| Widget | Purpose |
| --- | --- |
| `EmptyState` (`empty_state.dart`) | Shown when a query legitimately returns nothing. Every list in the app has one, and a new user sees these before they see anything else. |
| `ErrorView` (`error_view.dart`) | Failure state with a retry affordance. `details` renders in debug builds only — a stack trace is noise to a user and a support burden to you. `compact: true` for use inside a dashboard card. |
| `LoadingShimmer` (`loading_shimmer.dart`) | Placeholder block shown while a provider resolves. Deliberately dependency-free: a pulsing opacity reads as "loading" without adding a package for one effect. |
| `FilterChipGroup<T>` (`filter_chip_group.dart`) | A labelled row of single-select filter chips plus an "All" chip that clears the filter. Shared by the Library page and the exercise picker so both filter identically. Needs only `==` and a label function, so it works for enums and value classes alike. |
| `kChartNoLongPress` (`chart_gestures.dart`) | Not a widget — a `Duration` constant that neutralises `fl_chart`'s long-press recognizer, which otherwise wins the gesture arena against the enclosing scrollable and leaves the page feeling stuck over charts. Pass as `longPressDuration:` on any touch-enabled chart. |

---

## Feature widgets

### Tracker

| Widget | Purpose |
| --- | --- |
| `ExerciseDraftCard` (`draft_editor_widgets.dart`) | One exercise and its sets within a draft. Shared by the active-session and edit screens, both backed by a `DraftEditorController`. Laid out as a small table so column names appear once and the set rows stay scannable mid-set. |
| `DraftSetRow` (`draft_editor_widgets.dart`) | A single set row. Owns and disposes its own controllers (ADR-5) and converts the entered weight into kilograms here — ADR-1's boundary, so a pound value never reaches the controller. |
| `InlineRestTimer` (`draft_editor_widgets.dart`) | A compact rest countdown. Reuses `TimerEngine` but deliberately creates no saved session and uses no notifications, audio or wakelock. Rendered once per exercise rather than between every pair of sets. |
| `HistoryCalendar` (`history_calendar.dart`) | Month grid marking every day with at least one logged workout, with tap-to-drill-in. A second lens on data the list view already shows — no new query, no new persisted state. |
| `WorkoutXlsxImportAction` (`workout_xlsx_import_action.dart`) | Preview-first importer for a historical XLSX workout log: parse, show what will land, then write only on confirmation. |

### Dashboard, Progress, Profile

| Widget | Purpose |
| --- | --- |
| `SummaryCard` (`dashboard/.../summary_card.dart`) | One dashboard metric tile: a `MetricBlock` on an `AppCard`. Each card owns its loading and error state so one failing query degrades a single tile instead of blanking the dashboard. |
| `BodyMetricTile` (`progress/.../body_metric_widgets.dart`) | One logged measurement with its edit/delete menu. Shared by the Progress page's recent list and the full history page so the two cannot drift apart. |
| `ValuePillRow` (`profile/.../value_pill.dart`) | One labelled row of the Personal Details form: icon, label, and a tappable pill showing the current value (or a placeholder such as "Set" when empty). |

### Auth and Settings

| Widget | Purpose |
| --- | --- |
| `AuthFormScaffold` (`auth/.../auth_form_scaffold.dart`) | Shared shell for the three auth screens. They differ only in fields and primary action, so title, intro copy, error banner and scroll behaviour live here instead of being copied three times and drifting. |
| `AccountSection` (`settings/.../account_section.dart`) | The Settings entry point for accounts and personal details. Three states: signed out, signed in, and Supabase-not-configured — the last says so plainly rather than offering a button that can only fail. |
| `CloudBackupSection` (`settings/.../cloud_backup_section.dart`) | Manual whole-database backup and restore against the signed-in account. Explicitly temporary (PLAN.md Phase 5); the copy says "while the app is in testing" out loud, because a backup people over-trust is worse than one whose limits they know. |
| `DataManagementSection` (`settings/.../data_management_section.dart`) | Export / import / delete-all-data controls (ADR-7). Kept as its own widget so `settings_page.dart` stays a plain list of sections while the dialog flow lives here. |

---

## Conventions

- **`core/widgets` never imports `features/`.** If a shared widget seems to
  need a domain enum, add a neutral one next to the widget and map to it at
  the call site — `TrendDirection` is the worked example.
- **Localize at display time.** Widgets take already-localized strings, or
  read `context.l10n` themselves. They never take a translation key.
- **Formatted values in, not raw doubles.** `Stat.value`, `MetricBlock.value`
  and friends expect a formatted string; callers pass `'—'` for a genuinely
  absent value rather than passing null and hoping.
- **`PageBody` uses `heightFactor: 1` deliberately.** A plain `Center` expands
  to the tallest constraint it is offered, which makes a short child claim the
  whole screen and swallow every tap above it.
