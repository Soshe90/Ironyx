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
| `AppCard` (`app_card.dart`) | The standard surface for grouped content: 16dp radius; white with a soft shadow in light mode, a hairline outline in dark. Reserve it for real objects (a workout, an exercise being logged) — form fields and single rows sit on the page. Tappable variants get an ink ripple and a semantics label so a screen reader announces the card as a single button. |
| `SectionHeader` (`section_header.dart`) | Titles a group of content, with an optional trailing action and an optional info affordance. Gives the app one vertical rhythm for section breaks. |
| `StickyActionBar` (`sticky_action_bar.dart`) | Pins a screen's primary commit action (finish, save) above the fold instead of leaving it at the bottom of a list that grows as you add exercises. |
| `SheetHandle` (`sheet_handle.dart`) | The grab handle at the top of a bottom sheet. Decorative — excluded from semantics so the sheet's heading is what gets announced. |
| `Breakpoint`, `BreakpointContext` (`responsive.dart`) | Layout breakpoints (`compact` / `medium` / `expanded`, switching at 768 and 1200 dp) plus `context.breakpoint` and `context.contentMaxWidth`. Designed for 360 dp, 768 dp and 1440 dp; widget tests cover the dashboard at those widths, but a manual pass on real windows/devices is still open (`TODO.md` Priority 3). |

## Core — metrics and data display

| Widget | Purpose |
| --- | --- |
| `MetricBlock` (`metric_block.dart`) | Eyebrow label, large tabular number, caption, optional trend — the shape every fitness metric in this app takes. Deliberately *not* a card, so screens can render it straight onto a surface without nesting cards to show a number. |
| `MetricValue` (`metric_value.dart`) | A single-line metric number that scales down to fit instead of ellipsizing. Used by `MetricBlock`, `StatStrip` and the dashboard's volume headline; use it for any headline number that could meet a narrow tile or large system text. |
| `StatStrip`, `Stat` (`stat_strip.dart`) | A row of small stats separated by hairline rules ("volume / sets / duration"). Wraps to a second line rather than shrinking text below legibility. At most one `Stat` per strip sets `emphasis`. |
| `ValueRow` (`value_row.dart`) | The one style for a "label … value" line inside a card (a date and its volume, an exercise and its ratio), with an optional caption under the label. Replaces dense `ListTile`s, whose own inset misaligned rows with their card heading and whose unstyled trailing text made the value smaller than the label. |
| `TrendBadge`, `TrendDirection` (`trend_badge.dart`) | Small coloured pill with a direction arrow for "up / down / flat vs. last period". The enum is domain-neutral on purpose — features map their own trend types at the presentation boundary, which is what keeps `core/` free of feature imports. |
| `PrBadge` (`pr_badge.dart`) | Marks a workout that set a new estimated-1RM personal record. Uses the dedicated `AppColors.personalRecord` accent so a PR reads identically everywhere and never collides with the primary action colour. |
| `Sparkline` (`sparkline.dart`) | A minimal, axis-free trend line for embedding in a card. Not a chart — use `fl_chart` directly when you need axes, tooltips or touch. |
| `MetricExplainer`, `MetricInfoButton`, `showMetricExplainer` (`metric_explainer.dart`) | The "what does this number mean?" sheet: plain-language summary, the formula rendered as an illustration, a worked example with real numbers, how-to-read bullets, and a caveat. Attach one to any metric whose name is jargon. |

## Core — state handling

| Widget | Purpose |
| --- | --- |
| `EmptyState` (`empty_state.dart`) | Shown when a query legitimately returns nothing. Every list in the app has one, and a new user sees these before they see anything else. |
| `ErrorView` (`error_view.dart`) | Failure state with a retry affordance. `details` renders in debug builds only — a stack trace is noise to a user and a support burden to you. `compact: true` for use inside a dashboard card. |
| `UncaughtErrorView` (`uncaught_error_view.dart`) | What `ErrorWidget.builder` shows in place of a widget that failed to build. Not for use in a screen: use `ErrorView` for a failure you can handle. Depends on no ancestor, so it works above `MaterialApp`. Debug builds show the exception, the first error of the burst, the widget blamed and the top stack frames; release builds show one translated sentence and nothing about the error. |
| `LoadingShimmer` (`loading_shimmer.dart`) | Placeholder block shown while a provider resolves. Deliberately dependency-free: a pulsing opacity reads as "loading" without adding a package for one effect. |
| `FilterChipGroup<T>` (`filter_chip_group.dart`) | A labelled row of single-select filter chips plus an "All" chip that clears the filter. Shared by the Library page and the exercise picker so both filter identically. Needs only `==` and a label function, so it works for enums and value classes alike. |
| `SegmentedPills<T>`, `PillSegment` (`segmented_pills.dart`) | Single-select switch for what one view shows (a date range, which metric a chart plots): a quiet filled track with the chosen segment tinted like the navigation bar's indicator. Segments share the width, a long label shrinks rather than wraps, and each is a full 48 dp target. Not a filter (`FilterChipGroup`) and not navigation. Used by Progress for the range and the in-card chart switches. |
| `kChartNoLongPress` (`chart_gestures.dart`) | Not a widget — a `Duration` constant that neutralises `fl_chart`'s long-press recognizer, which otherwise wins the gesture arena against the enclosing scrollable and leaves the page feeling stuck over charts. Pass as `longPressDuration:` on any touch-enabled chart. |

---

## Feature widgets

### Tracker

| Widget | Purpose |
| --- | --- |
| `ExerciseDraftCard` (`draft_editor_widgets.dart`) | One exercise and its sets within a draft. Shared by the active-session and edit screens, both backed by a `DraftEditorController`. Laid out as a small table so column names appear once and the set rows stay scannable mid-set. |
| `DraftSetRow` (`draft_editor_widgets.dart`) | A single set row. Owns and disposes its own controllers (ADR-5) and converts the entered weight into kilograms here — ADR-1's boundary, so a pound value never reaches the controller. |
| `InlineRestTimer` (`draft_editor_widgets.dart`) | A compact rest countdown. Reuses `TimerEngine` but deliberately creates no saved session and uses no notifications, audio or wakelock. Rendered once per exercise rather than between every pair of sets. |
| `HistoryCalendar` (`history_calendar.dart`) | Month grid marking every day with at least one logged workout, with tap-to-drill-in. A second lens on data the list view already shows — no new query, no new persisted state. Hidden behind a toggle in the History header so the list stays above the fold. |
| `WorkoutXlsxImportAction` (`workout_xlsx_import_action.dart`) | Preview-first importer for a historical XLSX workout log: parse, show what will land, then write only on confirmation. The Workouts tab reaches it from the History menu through the static `run`, which takes the caller's context because a menu item's own is gone once the menu closes. |

### Library

| Widget | Purpose |
| --- | --- |
| `showExerciseDetailSheet`, `ExerciseDetailSheet` (`library/.../exercise_detail_sheet.dart`) | The "how to do it" sheet: media, muscles, equipment, ordered steps and a YouTube search. The one entry point for every screen that names an exercise, so Library, a program day, a saved workout and the live session all show the same thing. An id that no longer resolves gets the not-found state. Lives in Library rather than `core/` because it needs Library's catalogue localisation. |
| `ExerciseInfoTapTarget`, `ExerciseInfoIcon` (`exercise_detail_sheet.dart`) | Makes an exercise heading open that sheet: ≥48 dp target, ink ripple, merged button semantics. The ⓘ icon is both the visible cue and the screen-reader label ("How to do …"). Used by Programs and Tracker; wrap the heading only, never a whole card with set rows inside. |
| `ExerciseThumbnail`, `exercisePictureUrl`, `equipmentIcon` (`library/.../exercise_media.dart`) | Exercise picture with loading and fallback states (including YouTube's grey 120×90 "missing" placeholder), shared by the Library grid and the detail sheet. |

### Dashboard, Progress, Profile

| Widget | Purpose |
| --- | --- |
| `SummaryCard` (`dashboard/.../summary_card.dart`) | One dashboard metric tile: a `MetricBlock` on an `AppCard`. Each card owns its loading and error state so one failing query degrades a single tile instead of blanking the dashboard. |
| Dashboard hero and week card (private, `dashboard_page.dart`) | `_TodayCard` (gradient hero: Start/Resume as the one filled button, start-from-program as a text action, and a caption that says how long ago the last workout was), `_WeekBody` (this week's volume, its badge comparing with last week up to the same moment, captioned "Same point last week") with `_SessionGoal` (sessions x / weekly target as one segment per target session; target from `profiles.weekly_session_target`, default 3, clamped 1–7) and `_WeeklyBreakdown` / `_WeekdayCell` (day strip starting on the day chosen in Settings, bucketed in the device's timezone, in four states: trained, today, a past day missed, a day to come). `_ProgressSection` is a two-by-two of `SummaryCard`s (Est. 1RM, body weight, streak, average duration). Deliberately **private and not in `core/`**: they are one screen's layout, and each is fed by its own provider (no single `DashboardData` model — see `TODO.md` cross-check). At the expanded breakpoint the page uses a two-column primary row inside `PageBody`'s 1100 dp cap. |
| `BodyMetricTile` (`progress/.../body_metric_widgets.dart`) | One logged measurement with its edit/delete menu. Shared by the Progress page's recent list and the full history page so the two cannot drift apart. |
| `ProgressOverviewHero` (`progress/.../progress_visuals.dart`) | Top of the Progress page: total volume for the selected range, a strip of the weeks behind it, then workouts, weekly average (`averageSessionsPerWeek`, the same figure as the frequency card) and PRs. After a break that leaves the range empty it adds "Last workout: …" (Home's caption string). Same gradient as the dashboard's `_TodayCard`. Reads the weekly providers the page already watches, plus the first and last workout dates (one `MIN` / `MAX` each); a failed provider shows `—` and the owning section reports the error. The strip always runs left to right, matching the `fl_chart` charts, which do not mirror in Arabic. |
| `ProgressChapter` (`progress/.../progress_visuals.dart`) | Where a Progress chapter (Strength / Volume / Habits / Body) begins: a wider gap and, after the first, a hairline. Draws no title, since the pinned tabs name the chapter; the title reaches screen readers as a semantics header, and the page keys its chapter jumps and scroll tracking on it. |
| `ProgressChapterTabs` (`progress/.../progress_visuals.dart`) | The chapters as a row of tabs pinned above the Progress scroll view, under the range. Tapping one asks the page to scroll there and the selection follows the reader's position; none is selected above the first chapter. Not a `TabBar` (one page, not separate views) and never scrolls sideways, so the page's own scroll view stays the first `Scrollable` in the tree. |
| `ProgressChartCard`, `ProgressChartLoading`, `ProgressPlotLoading`, `ProgressChartEmpty`, `ProgressChartError`, `DatedLineChart`, `WeeklyBarChart` (`progress/.../widgets/progress_charts.dart`) | The frame every Progress chart sits in (headline, optional trend and header, then the plot) with its loading, empty and error states, and the two `fl_chart` plots: a line over a time-proportional x axis, and one bar per zero-filled week. Both take values as stored (kilograms) and a `displayScale` for the reader's unit, and step their value axis with `niceAxisStep` (`chart_axis.dart`) so ticks are round in that unit. Each plot reaches a screen reader as one sentence (range, latest, lowest, highest; `progressChartSemantic`) with its ticks excluded, since the points exist only for touch. Kept in the feature: each encodes Progress rules (week labels, PR dots, the newest bar in full colour). |
| `LiftPickerField`, `showLiftPicker`, `LiftPickerSheet` (`progress/.../widgets/lift_picker.dart`) | The lift chooser on the lift chart: a field that looks like a form field and opens a bottom sheet of the lifts with logged sets, most-trained first, with session counts and the current one marked. Past `liftPickerSearchFrom` (8) lifts it adds a search box that matches every typed word against the shown and the stored name, with Arabic alef, teh marbuta and diacritics folded (`foldForSearch`). Only logged lifts: the Library's `ExercisePickerSheet` searches the whole catalogue, and a lift never trained has nothing to chart. The field is one semantics button ("Exercise: …") that carries its own tap action, because excluding the InkWell's semantics would drop it. |
| Progress sections (`progress/.../sections/`) | One library per chapter, each exposing its section widgets to the page: `insights_section.dart`, `strength_sections.dart` (strength change, relative strength, lift chart), `volume_sections.dart`, `habit_sections.dart`, `body_section.dart`. Each section owns its loading, empty and error state, so one failing query degrades one card. `progress_page.dart` keeps only the scaffold, the pinned range and chapter tabs, and the scroll tracking. |
| `ShareBarRow`, `ProportionBar`, `RatioGauge`, `WeekdayBars`, `ProgressStatTile`, `ProgressIconChip` (`progress/.../progress_visuals.dart`) | Progress visuals drawn with plain widgets instead of `fl_chart`, so every figure is real text for screen readers and tests: ranked muscle share (a `ShareBarRow` given `onTap` becomes a button that marks itself `selected`; the muscle card uses that to show one group's weeks), rep-range split, balance ratio against its shaded 0.75–1.33 band, training days scaled to the busiest weekday, consistency figures, and insight icons. Bars and the gauge fill from the reading start, so they mirror in Arabic. Kept in the feature rather than `core/` because each encodes a Progress-specific idea. |
| `ValuePillRow` (`profile/.../value_pill.dart`) | One labelled row of the Personal Details form: icon, label, and a tappable pill showing the current value (or a placeholder such as "Set" when empty). |

### Auth and Settings

| Widget | Purpose |
| --- | --- |
| `AuthFormScaffold` (`auth/.../auth_form_scaffold.dart`) | Shared shell for the four auth screens (sign in, sign up, forgot password, reset password). They differ only in fields and primary action, so title, intro copy, error banner and scroll behaviour live here instead of being copied four times and drifting. |
| `AccountSection` (`settings/.../account_section.dart`) | The Settings entry point for accounts and personal details. Three states: signed out, signed in, and Supabase-not-configured — the last says so plainly rather than offering a button that can only fail. When signed in it also carries **Delete account**, behind a typed `DELETE` confirmation: it removes the remote account and cloud backup only, and says local workouts stay until removed in Data Management (store-required in-app deletion path; ADR-8 amendment). |
| `AboutSection` (`settings/.../about_section.dart`) | The free-exercise-db attribution dialog and the open-source licences page (Flutter's `showLicensePage`, which also shows `kAppVersion`). |
| `CloudBackupSection` (`settings/.../cloud_backup_section.dart`) | Manual whole-database backup and restore against the signed-in account. Explicitly temporary (TODO.md Roadmap Phase 5); the copy says "while the app is in testing" out loud, because a backup people over-trust is worse than one whose limits they know. |
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
