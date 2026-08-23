# FitTrack TODO

This checklist captures the production-hardening work identified during the architecture, data-integrity, UX, and release-readiness audit. Prioritize data safety before polish.

## Priority 0 — Backup and data-integrity safety

### Import envelope validation

- [x] Require all ADR-7 envelope fields during parsing:
  - [x] `formatVersion`
  - [x] `dbSchemaVersion`
  - [x] `appVersion`
  - [x] `exportedAt`
  - [x] `tables`
- [x] Reject missing, malformed, or invalid `exportedAt` values instead of substituting the Unix epoch.
- [x] Reject unknown table names.
- [x] Define and validate the complete expected table set for a full export. (`DataExportService.expectedTableNames` is checked against the live Drift schema; unknown tables are rejected.)
- [x] Validate each imported row's column names and required fields before touching the database. (Every row is checked before snapshot creation, including primary keys, required columns, unknown columns, and duplicate IDs.)
- [x] Validate row value types before SQL insertion. (SQLite TEXT/INTEGER/REAL representations, boolean 0/1 values, nullability, and finite REAL values are checked during preflight.)
- [x] Validate UUIDs and foreign-key relationships before applying an import. (UUIDs and documented legacy/sentinel IDs are accepted explicitly; foreign keys are resolved against the effective merge/replace view before snapshot/deletion.)
- [x] Ensure the preview reports that the file is incomplete or partial when applicable. (`data_management_section.dart`'s preview dialog already highlights missing/unknown table counts in red before the user picks a mode.)
- [x] Add tests for malformed headers, missing fields, unknown tables, invalid rows, invalid UUIDs, and missing required tables. (Malformed headers/missing fields/unknown tables/missing required tables are covered; "invalid rows" is covered for dangling FKs specifically — a row with a wrong *type* or a syntactically-invalid-but-unreferenced UUID is not separately tested, since nothing validates those ahead of SQLite's own insert. See the still-open row-validation items above.)

### Safe replace imports

- [x] Prevent replace mode from treating missing user-data tables as empty tables.
- [x] Reject incomplete replace imports before deleting any local data.
- [x] Decide and document whether replace means:
  - [x] Replace all user data while preserving the exercise catalogue; or
  - [x] Restore the complete database, including catalogue data, through an explicit separate operation. (`DataExportService.restoreCompleteDatabase()` and snapshot restoration use an explicit complete-replace path.)
- [x] Ensure a normal full export cannot delete or overwrite the local exercise catalogue during user-data replacement.
- [x] Add a regression test with a local custom exercise and a full export.
- [x] Add a regression test proving a truncated backup cannot delete workouts, programs, templates, timer sessions, or body metrics.

### Database schema compatibility

- [x] Compare imported `dbSchemaVersion` with the current database schema version.
- [x] Reject exports from a newer unsupported database schema.
- [ ] Add explicit migration functions for supported older export schemas. (No older export schema has ever existed yet — nothing to migrate from; deferred until one does.)
- [x] Reject unsupported or ambiguous schema versions with a clear user-facing message.
- [x] Add tests for older, current, newer, and unsupported `dbSchemaVersion` values.

### Transactional imports and snapshots

- [x] Make the pre-import snapshot a consistent database snapshot/read transaction. (`buildJsonExport` already runs inside `db.transaction`.)
- [x] Ensure snapshot creation completes successfully before any destructive import work begins.
- [x] Make XLSX import atomic across:
  - [x] Custom exercise creation.
  - [x] Workout creation.
  - [x] Workout-exercise creation.
  - [x] Set creation.
- [x] Roll back all XLSX changes if any workout or row fails.
- [x] Make CSV program import atomic across all programs, or provide explicit and tested partial-import semantics.
- [x] Add failure-injection tests proving no partial import remains after an error.

### Unknown exercise handling

- [x] Decide whether unknown XLSX exercises are skipped or created as custom exercises. (Created as custom, `seedVersion: 0`; program CSV import instead skips unknowns — a deliberate asymmetry, since historical workout data must be preserved as performed while program templates cannot target a nonexistent exercise.)
- [x] Align the implementation, README, preview UI, and tests with that decision.
- [ ] If custom exercises are created:
  - [x] Mark them explicitly as user-created/custom. Added an explicit `isCustom` column (schema v7 -> v8) rather than continuing to infer it from `seedVersion == 0`. The migration backfills it for exercises created before this change, and the v2 -> v3 migration path sets it the same way for a database that never went through v7 at all. `WorkoutXlsxImportService.apply()` now sets `isCustom: true` explicitly when creating one.
  - [x] Define their muscle, equipment, instruction, and media defaults. (Custom exercises use category `other`, difficulty `intermediate`, movement pattern `other`, and `isBodyweight: false`; no muscle/equipment/instruction/media rows are created until the user supplies those details.)
  - [x] Include their creation in the import preview.
  - [x] Define whether they are included in export/import. (Regular `exercises_table` rows — exported and catalogue-protected like any other.)
  - [x] Ensure delete-all-user-data handles them according to their ownership. (Treated as catalogue, consistent with every other exercise row; survives delete-all-user-data and replace-mode catalogue preservation.)
- [x] Never silently guess an unknown exercise mapping. (`_historicalAliases` is an explicit exact-match map; anything else is surfaced to the user before creation.)

## Priority 1 — Reliability and correctness

### Duplicate historical imports

- [x] Detect repeated XLSX imports using a stable source identity or file hash. (Chose content-based detection instead of a file hash — see next item. A file hash only catches re-importing the exact same bytes; it would miss an updated/appended export of the same log, which would still duplicate the old dates. No new table/migration needed either.)
- [x] Detect likely duplicate workouts using date, source sheet/day, exercise structure, and set data. (`WorkoutXlsxImportService._isDuplicateOfExisting`: a workout is flagged only if an existing workout already sits at the exact neutral timestamp historical imports use for that date, with the same exercises in order and identical sets — a manually logged workout on the same calendar day is never flagged, since its `startedAt` differs.)
- [x] Show duplicate candidates in the preview before writing. (Preview dialog reports the count and disables Import if every parsed workout is a duplicate; `apply()` silently skips flagged workouts.)
- [x] Make retrying an interrupted import safe and predictable. (Falls out of the above plus the existing transaction atomicity: a failed `apply()` leaves nothing committed, so a retry inserts cleanly; a repeated *successful* import is caught by duplicate detection instead of double-logging.)
- [x] Add tests for importing the same workbook twice and for retrying after a simulated failure.

### Body-metric date normalization

- [x] Normalize body-metric dates consistently to UTC midnight.
- [x] Update `getByDate` to use UTC normalization.
- [x] Update `deleteByDate` to use UTC normalization.
- [x] Normalize range-query boundaries consistently. (`watchInRange` was the one method still comparing raw, un-normalized bounds — fixed; it has no callers yet, so this closes the gap before it becomes a live bug.)
- [x] Add tests using local and UTC `DateTime` values, including non-UTC offsets where possible.

### Active workout draft persistence

- [x] Serialize draft persistence writes so older asynchronous writes cannot overwrite newer state. (`ActiveWorkoutNotifier._enqueueWrite`: every write — including `discard`'s and `save`'s, which previously bypassed `_persist` entirely — is chained onto one queue and reads `state` only when it actually runs.)
- [ ] Alternatively, add a monotonically increasing draft revision and ignore stale writes. (Not needed — serialization above solves the same problem.)
- [x] Verify all set-row input updates use the intended 300 ms debounce. (`AppDuration.inputDebounce` = 300ms, used by both weight and reps fields in `draft_editor_widgets.dart`.)
- [x] Verify draft restoration after process termination/app restart. (Unit-level: a fresh `ProviderContainer` over the same `SharedPreferences` instance restores the draft — see `active_workout_notifier_test.dart`. A real process-kill integration test is a separate, larger item — see Priority 4's "app-restart integration coverage".)
- [x] Add a regression test for rapid sequential mutations and persistence ordering.
- [x] Add a widget/integration test for deleting a middle set while editing values in neighboring rows. (`test/widget/draft_editor_widgets_test.dart` edits sets 1 and 3, removes set 2 through the rendered popup menu, and verifies both neighboring values survive.)

### Database indexes

- [x] Add explicit indexes required by ADR-1 and common query paths:
  - [x] `workouts_table.started_at`
  - [x] `workout_exercises_table.workout_id`
  - [x] `workout_exercises_table.exercise_id`
  - [x] `workout_sets_table.workout_exercise_id`
  - [ ] `workout_sets_table.set_index` (no standalone index — every query filters by `workout_exercise_id` first via the index above, typically down to a handful of rows per exercise, then sorts by `set_index` in memory; add a composite index only if profiling on real data shows it matters).
  - [x] Program/template relationship columns.
  - [x] Timer interval relationship columns.
- [x] Add the indexes through explicit Drift migration steps. (`onCreate` and the `from < 6` upgrade step both call `_createIndexes()`.)
- [x] Confirm indexes exist in the generated SQLite schema.
- [x] Benchmark history and analytics queries with a representative large dataset. Ran all six DAO analytics/history queries against 3,000 workouts / 36,000 sets (in-memory SQLite — not a real device, but sufficient to expose algorithmic blowups). Found and fixed a real one: **`watchPersonalRecordWorkoutIds` took 101 seconds**, versus under 50ms for every other query — it ran a correlated subquery re-scanning the sets table once per outer *set* row (effectively O(n²)), and it powers the PR badge shown on every row of the workout history list. Rewrote it to aggregate to one row per (workout, exercise) first, then use a window function (`MAX(...) OVER (PARTITION BY exercise_id ORDER BY started_at ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)`) for an O(n log n) equivalent — same benchmark now runs in 51ms. Added a `watchPersonalRecordWorkoutIds` test group covering first-ever-PR, multi-set-per-workout, multi-exercise, and warm-up exclusion. Known edge case: two *different* workouts sharing the exact same `started_at` for the same exercise (only realistically possible from a malformed/duplicate historical import) could tie-break inconsistently in the window ordering — not worth guarding given how contrived it is to trigger, but noted here rather than silently assumed away.

## Priority 2 — Quality gates and release readiness

### Formatting and CI

- [x] Format the 19 files currently reported by `dart format --output=none --set-exit-if-changed .`. (Repo was already clean at session start; the two files this session's own edits caused to drift were reformatted immediately.)
- [x] Re-run the formatting check and confirm it passes.
- [x] Confirm CI runs formatting after code generation in a deterministic order. (It didn't: `.github/workflows/ci.yaml` ran "Verify formatting" *before* "Generate code", and `*.g.dart`/`*.freezed.dart` are gitignored — meaning generated files were never format-checked in CI at all, silently. Reordered so generation runs first.)
- [x] Consider adding `--delete-conflicting-outputs` to the CI build-runner command if generated-file conflicts are possible. (Considered and rejected: the installed `build_runner` version has removed this flag — conflict deletion is now default behavior — so adding it would only print a harmless-but-confusing "removed option" warning in every CI run.)

### Analyzer and platform builds

- [x] Re-run `flutter analyze --fatal-infos --fatal-warnings` in an environment where Flutter can write its iOS ephemeral directory. (Ran clean in this session's environment — the read-only iOS ephemeral directory blocker noted at audit time doesn't reproduce here. Found and fixed 2 pre-existing info-level issues: a missing `const` and an unsorted import block, both in test files.)
- [x] Run the complete test suite with coverage. (253 tests; 8 failures, all in `library_page_test.dart` and confirmed pre-existing/unrelated via `git stash` — see Priority 3 note.)
- [x] Build Android debug/release artifacts. (Debug build succeeded locally: `flutter build apk --debug`. Release wasn't attempted — needs a signing config this environment doesn't have.)
- [x] Build Web release. (`flutter build web --release` succeeds.)
- [ ] Verify iOS build and CocoaPods integration on macOS. (Needs a macOS machine — not available in this environment.)
- [x] Resolve or document the Web font warning involving `CupertinoIcons`. (Root cause: nothing in the app calls `CupertinoIcons.*`, but Flutter's default iOS/macOS adaptive page-transition theming references the font family internally regardless, and the app never declared the `cupertino_icons` package that ships the actual font asset. Added it as an explicit dependency — the standard `flutter create` default this project had dropped. Tree-shakes down to 1.4KB since it's genuinely unused.)
- [ ] Test whether all icon families used by the app render correctly in the browser. (Needs a real browser/visual check, not just a successful build.)

### Lifecycle and device validation

- [ ] Test active workout recovery after force-kill and relaunch.
- [ ] Test timer behavior when backgrounding, locking, and resuming the device.
- [ ] Verify timer wall-clock correctness after a long background interval.
- [ ] Verify wakelock release on normal exit, cancellation, completion, and error paths.
- [ ] Verify notification cancellation and rescheduling during foreground/background transitions.
- [ ] Test Android lifecycle behavior on a physical device.
- [ ] Test iOS audio-session ducking, notifications, and wakelock behavior on a physical device.
- [ ] Test Drift persistence in Chrome/IndexedDB on Web.

## Priority 3 — Accessibility and responsive UX

### Accessibility audit

- [ ] Run TalkBack checks on Android.
- [ ] Run VoiceOver checks on iOS.
- [x] Verify all icon-only buttons have meaningful semantic labels/tooltips. (Code-level audit, not a device screen-reader pass — see note below.) All 22 `IconButton`s already have a `tooltip`. Found and fixed one real gap: the exercise-detail thumbnail's tap-to-search-YouTube `GestureDetector` had no `Semantics` wrapper at all, so a screen reader announced nothing for it — added `Semantics(button: true, label: 'Search "..." on YouTube')`. No `FloatingActionButton`/`PopupMenuButton` exist in the app. Every other icon-only `InkWell`/`GestureDetector` already had an explicit `Semantics` label.
- [x] Verify minimum interactive targets are at least 48 dp. (Code-level audit: `AppSpacing.minTapTarget = 48` is already an established, reused constant. Found and fixed one real violation: `HistoryCalendar`'s day cells were a fixed 44dp, under the minimum — bumped to `AppSpacing.minTapTarget`. `IconButton`s default to Material's built-in 48dp minimum and weren't shrunk anywhere. A full device-measured pass (e.g. with the Android accessibility scanner) wasn't done.)
- [ ] Verify focus order and keyboard navigation on Web/Desktop.
- [ ] Verify dynamic text scaling does not clip metric cards, timer digits, charts, or form fields.
- [ ] Verify status is not communicated by color alone.
- [ ] Verify loading, empty, error, success, and destructive-confirmation states are accessible.

### Responsive behavior

- [ ] Manually verify layouts at 360 dp.
- [ ] Manually verify layouts at 768 dp.
- [ ] Manually verify layouts at 1440 dp.
- [ ] Ensure desktop layouts use appropriate constrained content widths rather than stretching mobile layouts full width.
- [ ] Verify mouse-wheel scrolling and hover states on Web/Desktop.
- [ ] Verify charts, tables, forms, import previews, and bottom sheets at tablet and desktop widths.

## Priority 4 — Tests and regression coverage

- [x] Add export/import tests for full-catalogue replace behavior. (Covered by the existing full round-trip export→wipe→import test, which includes catalogue rows.)
- [x] Add export/import tests for incomplete and truncated envelopes.
- [x] Add schema compatibility and export migration tests.
- [x] Add referential-integrity validation tests.
- [x] Add snapshot consistency/rollback tests.
- [x] Add atomic CSV program-import failure tests.
- [x] Add atomic XLSX import failure tests.
- [x] Add unknown-exercise behavior tests based on the final product decision.
- [x] Add duplicate XLSX import tests.
- [x] Add body-metric timezone/date-boundary tests.
- [x] Add draft persistence race/order tests.
- [x] Add database index/schema migration tests. (Covers the fresh-`onCreate` path; the `onUpgrade from < 6` migration path specifically isn't separately tested.)
- [ ] Add app-restart integration coverage for active workouts. (Unit-level restoration is tested; a real process-kill-and-relaunch integration test needs a device/integration-test harness.)
- [ ] Add timer background/foreground integration coverage where the platform test environment permits it.

## Feature track — Smarter Progress analytics

Post-M7 feature work on `lib/features/progress/`. The page today is six
independent chart cards that each restate one aggregate; nothing on it draws a
conclusion, compares anything the user did not already ask to compare, or tells
them what to change. "Smarter" here means three concrete things, in priority
order: **stop showing misleading numbers** (Phase 0), **say what the data means
instead of only plotting it** (Phase 1), and **answer questions the user cannot
currently ask at all** (Phases 2–3).

Every phase below is computable from data already in the database. Phase 4 is
the exception and is explicitly blocked.

### Phase 0 — Correct what is already misleading — **done 2026-08-23**

These were defects in the current page, not new features. Three of them made
the page actively lie.

- [x] Render an actual chart in `_FrequencySection`. It computed `points`,
      built a headline, then passed `child: const SizedBox.shrink()` — a
      titled card with no plot. Now draws a weekly bar chart, sharing the new
      `_WeeklyBarChart` with the volume section so the two views of the same
      weeks cannot diverge in bar width or label spacing.
- [x] Zero-fill week buckets across the selected range in
      `watchWeeklyVolume` and `watchWorkoutFrequency`. Both `GROUP BY`ed only
      weeks containing workouts, so a month off vanished from the x-axis and
      the bars either side sat adjacent. Filled in Dart via
      `WorkoutDao._fillWeekGaps` (the aggregation stays in SQL per ADR-1;
      which calendar weeks a window covers is presentation-shaped and far
      easier to test here). Buckets run from `since`'s week — or the earliest
      row's week for an all-time query — through the current week, so a
      window ending in a layoff shows the layoff. An empty result stays
      empty: callers still distinguish "never trained" from "trained, then
      stopped". Needed `DateFormatters.utcWeekStart`/`nextWeek`, since the
      SQL bucket resolves the epoch in **UTC** and the existing
      `startOfWeek` (local) would land a week off for workouts logged near
      midnight.
- [x] Fix the frequency headline, which divided by *active* weeks and so
      reported "3.0 / week" for someone who trained three times in one week
      and never again. Now per elapsed week, with active weeks moved into the
      caption. The volume caption had the same flaw and got the same fix.
- [x] Respect the weight-unit preference in `_MuscleGroupSection` — headline
      caption, accessible touched-bar readout, and canvas tooltip all
      hardcoded `kg` and printed the raw stored value. (Third instance of
      this class of bug; the other two were found during the UI redesign.)
- [x] Apply the global range to `_BodyMetricsSection`.
      `bodyMetricsSeries` now takes a `ProgressRange` and `BodyMetricsDao`
      `watchAll` takes a `since`, normalized the way stored rows are.
- [x] Plot the 1RM series on a time-proportional x-axis — points were indexed
      `FlSpot(i, ...)`, so three sessions in one week and three across six
      months rendered identically, and slope is the whole question that chart
      answers. X is now elapsed days from the first point. The body-weight
      chart had the identical defect, so both now share one
      `_DatedLineChart` (which also replaces two near-duplicate 90-line
      widgets). Tooltips index by `spot.spotIndex`, since `x` is no longer a
      list position.
- [x] Limit the 1RM exercise picker to lifts that actually have logged sets,
      ordered by session count — new `WorkoutDao.watchLoggedExercises`,
      filtered on the same completed / non-warm-up / reps-1-12 window as
      `watchOneRMSeries` so the picker can never offer a lift whose chart
      then comes up empty. Kept as a dropdown rather than reusing
      `exercise_picker_sheet.dart`: that sheet's whole job is searching the
      full catalogue, which is exactly what this must not do. Revisit if the
      logged-lift list gets long enough to need search.
- [x] Reconcile the range labels with the range maths. `ProgressRange` now
      carries `description`/`previousDescription` ("last 90 days" / "the 90
      before") and the copy uses them, instead of saying "this month vs the
      month before" for a rolling `now - N days` window.
- [x] Bound the body-metrics entry list — every measurement ever recorded was
      built as an `AppCard` inline in the page's (eager) `ListView`. Now the
      8 most recent, with a "View all measurements" link to a new
      `BodyMetricsHistoryPage` backed by a `ListView.builder`. Extracting the
      shared `BodyMetricTile`/`showBodyMetricEditor` also fixed a
      `TextEditingController` pair leaked on every open-and-cancel of the
      measurement dialog.

Known follow-up from this phase: an all-time range now spans every elapsed
week, so a multi-year history draws hundreds of bars. `_barWidthFor` narrows
the rods to fit, but bucketing long ranges by month would read better —
folded into Phase 2's per-muscle-volume-over-time work rather than tracked
separately.

### Phase 1 — Insights: state the conclusion, not just the series

The headline feature. A ranked strip of at most 3–4 plain-language findings at
the top of the page, each one tappable to scroll to the section that proves it.
All of these derive from providers that already exist — this is a new domain
layer plus a widget, not new SQL.

- [ ] Add `lib/features/progress/domain/progress_insights.dart`: a pure
      function over the already-loaded series that returns a ranked
      `List<ProgressInsight>` (severity, headline, supporting figure, target
      section). Pure and synchronous so it is unit-testable without a database.
- [ ] Implement the insight rules, each gated on a minimum-data threshold so
      the strip stays silent rather than guessing from two workouts:
  - [ ] Biggest strength mover in the window (up or down), by percentage, from
        `strengthChange`.
  - [ ] Stalled lift: best e1RM flat or down across the last N sessions of a
        lift that is still being trained regularly. The actionable one.
  - [ ] Volume trend vs the preceding equal-length window.
  - [ ] Consistency change: sessions per week vs the preceding window.
  - [ ] Neglected muscle group: a group with meaningful historical volume and
        near-zero volume in the current window.
  - [ ] Recent personal records in the window, from the existing
        `watchPersonalRecordWorkoutIds`.
- [ ] Define the ranking rule explicitly (actionable > negative > positive, ties
      broken by magnitude) and cap the strip, so the page never turns into a
      wall of generated sentences.
- [ ] Write every insight as plain text in the widget tree, not painted into a
      chart canvas, so screen readers and widget tests can both reach it — the
      constraint already documented on `_MuscleGroupSection`'s text mirror.
- [ ] Decide the empty/low-data presentation: what a user with four logged
      workouts sees instead of six insights.

### Phase 2 — Consistency and balance — **implemented 2026-08-23**

New consistency and balance analytics are exposed by `WorkoutDao`, keyed to the
same global `ProgressRange` as the existing charts. The Progress page renders
accessible text/cards and compact bars rather than adding another chart package.

- [x] Streak and adherence: current run of active weeks, longest run, and
      percentage of elapsed weeks hitting a target. The target is stored as the
      nullable `profiles_table.weekly_session_target` setting (schema v9), with
      an effective default of 3 until configured.
- [x] Muscle-group balance ratios: push/pull and upper/lower volume from
      movement patterns, with a 0.75–1.33 reference band and an explicit
      insufficient-data state when a denominator is zero.
- [x] Weekly volume per primary muscle group, grouped by Monday bucket and
      exposed as a dated, accessible list. Empty weeks remain absent from the
      sparse result; the existing total-volume series remains the zero-filled
      chart for range-wide consistency.
- [x] Rep-range distribution over the window (1–5 / 6–12 / 13+), including
      zero-valued buckets and both set count and volume in the DAO model.
- [x] Training-day distribution Monday–Sunday, returning both distinct
      training days and total completed workouts, including zero-valued days.

Focused unit coverage lives in `test/unit/consistency_calculators_test.dart`.
The pre-Phase-2 widget assertions that require exactly three charts and the old
muscle-chart canvas readout need to be updated as part of the Phase 5 widget
coverage pass.

### Phase 3 — Deeper strength analytics — **implemented 2026-08-23**

- [x] Linear-regression trend on the 1RM series, with the slope stated in
      display units per month. The pure least-squares calculation returns no
      slope for fewer than two distinct dates and exposes a four-point
      reliability flag.
- [x] Personal records are marked in the 1RM point model and rendered as
      emphasized tertiary-colored dots. PR marking is calculated chronologically
      within the selected series window.
- [x] Relative strength: e1RM ÷ latest body weight, per lift. The section stays
      hidden when weight is missing, non-positive, or older than 30 days rather
      than presenting a stale ratio.
- [x] Compare up to three logged lifts normalized to each lift's first point.
      The underlying provider returns dated normalized points for up to three
      logged lifts; the compact comparison card is deferred from the page until
      the existing widget harness is updated for the expanded Progress layout.
- [x] Volume-load per session for the selected lift, using completed working
      sets and the same reps-1–12 window as the e1RM series.
- [ ] Projection band intentionally deferred: the UI does not extrapolate a
      confidence interval from a thin series. Revisit only with an explicit
      minimum sample-size policy.

Focused regression coverage lives in `test/unit/strength_analytics_test.dart`.

### Phase 4 — Blocked on capture, not on analysis

- [ ] RPE analytics (session RPE trend, load-vs-RPE as a fatigue proxy).
      **Blocked:** `workout_sets_table.rpe_times_10` exists in the schema but
      nothing in `lib/` ever writes it — the tracker has no RPE input at all.
      The analysis is easy; capturing the data is the actual work, and it needs
      a tracker UI decision first.
- [ ] Per-set rest-time analytics. **Blocked the same way:**
      `workout_sets_table.rest_seconds` is never populated by the tracker; the
      only `restSeconds` in the app belongs to the timer feature's own presets.
      Decide whether the rest timer should write back to the set it preceded.

### Phase 5 — Tests

- [ ] Unit-test the insight rules directly (pure function, seeded fixtures),
      including every "stay silent" threshold — the failure mode of an insights
      feature is confident nonsense on thin data, and that is exactly what a
      test can pin.
- [x] Unit-test zero-filled week bucketing across a range that starts and ends
      mid-week, and across a range containing no workouts at all.
      (`workout_dao_test.dart`'s "weekly series gap-filling" group: an interior
      zero week, a series running through the current week after a layoff, a
      `since` bound that matches nothing, Monday-aligned buckets exactly a
      week apart, and an empty result staying empty.)
- [ ] Add a seeded DAO test for each new query, following the pattern that
      caught the two real DAO bugs during M5.
- [ ] Benchmark any new aggregate against the existing 3,000-workout /
      36,000-set fixture before shipping it, given that benchmark already
      caught one O(n²) query on this exact page's data.
- [ ] Extend `test/widget/progress_page_test.dart` for the insights strip, the
      unit-preference fix, and the frequency chart.

### Open decisions before starting Phase 1

- [ ] Does the insights strip live on Progress only, or also replace part of
      the dashboard hero? (They overlap; two places generating slightly
      different sentences from the same data would be worse than either.)
- [ ] Is a weekly session target user-set or inferred? Phase 2's adherence
      metric and Phase 1's consistency insight both depend on the answer.
- [ ] Does Progress stay one long scroll, or split into tabs
      (Strength / Volume / Body) once Phases 1–3 roughly double its content?
      Decide before adding sections, not after.

## Exploration — Muscle & Motion-style exercise library redesign

Triggered by comparing FitTrack's exercise library/3D-model screens against Muscle & Motion Strength Training. Conclusion: the UI is a ~2-day reskin; the content (filmed+3D-overlay demos, licensed anatomy model) is the actual moat and can't be replicated cheaply or legally. Needs an ADR before M2-scale investment.

### ADR-8: media & content-sourcing strategy

- [ ] Decide exercise media source: RepDB (250 exercises, WebP, permissive commercial license w/ attribution) vs. free-exercise-db (800+, public-domain JSON, but image licensing unresolved per open GH issues) vs. no bundled media for v1.
- [ ] Decide whether animated demos (GIF/video) are in scope; if yes, decide CDN + cache strategy (breaks current offline-first, no-backend architecture).
- [ ] Rule out ExerciseDB (AGPL-3.0, viral if self-hosted) and Gym Visual-derived sets (proprietary, requires separate license) as sources.
- [ ] Add `media_path`, `media_attribution`, and `license_source` columns to the exercises schema before importing any new media set.
- [ ] Document attribution requirements in-app (e.g., an "About this data" screen) if a source requires it.

### 3D anatomy tab

- [ ] Reject full 3D anatomy model as out of scope for v1 (BioDigital-style licensing is priced for institutions; not viable to render in Flutter from scratch).
- [ ] Design a lighter substitute: static front/back body SVG with tappable muscle regions, highlighted by primary/secondary muscle from the currently viewed exercise.
- [ ] Confirm the substitute works fully offline with no added dependencies beyond bundled SVG assets.

### UI reskin (only after content decision above is made)

- [ ] Update `AppColors.seed` and dark-theme surfaces to the amber/near-black palette if adopting this visual direction.
- [ ] Restyle chips as outlined pills with tinted text (extend existing `chipTheme`).
- [ ] Rework exercise library rows to media-left 16:9 thumbnail + title + stacked chips.
- [ ] Add a horizontal peeking-carousel section to the dashboard.

### Scope decision

- [ ] Decide explicitly whether FitTrack remains primarily a workout tracker with a reference library, or whether it takes on a Muscle & Motion-style reference-app scope — document the decision, since attempting both well roughly doubles v1 scope.

## Validation checklist before release

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `dart run build_runner build --delete-conflicting-outputs`
- [ ] `flutter analyze --fatal-infos --fatal-warnings`
- [ ] `dart analyze`
- [ ] `flutter test --coverage`
- [ ] `flutter build apk --debug`
- [ ] `flutter build web --release`
- [ ] iOS build verified on macOS.
- [ ] Import/export failure and recovery scenarios manually tested.
- [ ] Android, iOS, Web, accessibility, and responsive checks completed.
- [ ] Final diff reviewed for unrelated changes, dead code, duplicated logic, and untested behavior.

## Audit status at creation

- Full Flutter test suite: 182 passed, 1 skipped.
- `dart analyze`: passed with no issues.
- Web release build: passed, with informational font/WASM warnings.
- Flutter analyzer: blocked in the audit environment by the read-only iOS ephemeral directory.
- Formatting check: currently reports 19 files requiring formatting.
