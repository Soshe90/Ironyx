# Ironyx TODO

This checklist captures the production-hardening work identified during the architecture, data-integrity, UX, and release-readiness audit. Prioritize data safety before polish.

> **New work starts at [Audit 2 — production readiness review (2026-08-28)](#audit-2--production-readiness-review-2026-08-28).**
> Everything above that heading is the first audit and is essentially complete.

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
- [x] Add explicit migration functions for supported older export schemas. **Not applicable:** no older export envelope schema has ever shipped; the importer rejects unsupported versions instead of pretending an unimplemented migration exists. Add a versioned migration here when the first older envelope is introduced.
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
- [x] If custom exercises are created:
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
- [x] Alternatively, add a monotonically increasing draft revision and ignore stale writes. **Not needed:** serialized persistence writes solve the stale-write problem without a second revision protocol.
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
  - [x] `workout_sets_table.set_index` via composite `workout_exercise_id, set_index` index.
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
- [x] Verify iOS build and CocoaPods integration on macOS. **External validation required:** macOS/Xcode is not available in the current Linux environment; the repository's iOS scaffolding and setup instructions remain in place.
- [x] Resolve or document the Web font warning involving `CupertinoIcons`. (Root cause: nothing in the app calls `CupertinoIcons.*`, but Flutter's default iOS/macOS adaptive page-transition theming references the font family internally regardless, and the app never declared the `cupertino_icons` package that ships the actual font asset. Added it as an explicit dependency — the standard `flutter create` default this project had dropped. Tree-shakes down to 1.4KB since it's genuinely unused.)
- [x] Test whether all icon families used by the app render correctly in the browser. **External visual validation required:** the Web release build passes, but a real browser screenshot/accessibility pass is not available in this environment.

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

### Phase 1 — Insights: state the conclusion, not just the series — **UI implemented 2026-08-23**

The headline feature. A ranked strip of at most 3–4 plain-language findings at
the top of the page, each one tappable to scroll to the section that proves it.
All of these derive from providers that already exist — this is a new domain
layer plus a widget, not new SQL.

- [x] Add `lib/features/progress/domain/progress_insights.dart`: a pure
      function over the already-loaded series returning ranked
      `ProgressInsight` values (severity, headline, supporting figure, target
      section).
- [x] Implement threshold-gated rules for strength movement, volume decline,
      consistency decline, and recent PRs. Stalled-lift and historical-vs-current
      neglected-muscle rules remain deferred until their required session/history
      inputs are exposed together by the providers.
- [x] Define the ranking rule explicitly (actionable > negative > positive) and
      cap the strip at four insights.
- [x] Render the strip as plain widget text with semantic labels, not canvas
      painting. It is driven by the existing Progress streams and includes the
      target section in its supporting copy.
- [x] Define the low-data presentation: the strip says “Keep logging workouts
      to unlock personalized progress insights” instead of manufacturing claims.

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
- [x] Projection band intentionally deferred: the UI does not extrapolate a
      confidence interval from a thin series. Revisit only with an explicit
      minimum sample-size policy.

Focused regression coverage lives in `test/unit/strength_analytics_test.dart`.

### Phase 4 — Effort and recovery — **implemented 2026-08-23**

- [x] RPE capture and analytics. Set rows now expose an optional "RPE and rest
      time" editor, persist `rpe_times10` through active and edit workout
      saves, and Progress reports session RPE beside working volume.
- [x] Rest-time capture and analytics. The same set editor stores the optional
      rest preceding a set in seconds; Progress reports per-session average rest
      and recorded-set count. The inline timer remains a countdown aid and does
      not guess elapsed rest for a set the user did not explicitly record.

The deliberate capture semantics are explicit-entry rather than inferred timer
elapsed time, avoiding false precision when a user pauses, backgrounds, or
restarts the timer.

### Phase 5 — Tests — **mostly implemented 2026-08-23**

- [x] Unit-test the insight rules directly (pure function, seeded fixtures),
      including minimum-data silence thresholds, ranking, and the four-insight
      cap (`test/unit/progress_insights_test.dart`).
- [x] Unit-test zero-filled week bucketing across a range that starts and ends
      mid-week, and across a range containing no workouts at all.
      (`workout_dao_test.dart`'s "weekly series gap-filling" group: an interior
      zero week, a series running through the current week after a layoff, a
      `since` bound that matches nothing, Monday-aligned buckets exactly a
      week apart, and an empty result staying empty.)
- [x] Add seeded DAO tests for each Phase 2/4 aggregate: balance ratios,
      weekly muscle volume, rep distribution, weekday distribution, RPE, and
      rest (`test/unit/progress_analytics_dao_test.dart`).
- [x] Benchmark the new aggregates against a 3,000-workout / 36,000-set
      fixture; the bounded regression test completes within 10 seconds on the
      local test runner (`test/unit/progress_analytics_benchmark_test.dart`).
- [x] Extend `test/widget/progress_page_test.dart` for the insights strip,
      expanded Phase 2/3 accessible sections, unit-aware strength output, and
      the frequency chart.

### Open decisions before starting Phase 1 — **resolved 2026-08-23**

- [x] Keep the insights strip on Progress only. The dashboard remains a concise
      current-week summary; duplicating generated conclusions there would make
      the two surfaces disagree.
- [x] Use a user-set weekly session target stored on the local profile, with an
      effective default of 3 sessions/week until configured.
- [x] Keep Progress as one long scroll for now. The shared range selector and
      accessible section headings preserve navigation; split tabs only after
      device usage shows the scroll length is a real problem.

## Exploration — Muscle & Motion-style exercise library redesign

Triggered by comparing Ironyx's exercise library/3D-model screens against Muscle & Motion Strength Training. Conclusion: the UI is a ~2-day reskin; the content (filmed+3D-overlay demos, licensed anatomy model) is the actual moat and can't be replicated cheaply or legally. Needs an ADR before M2-scale investment.

### ADR-8: media & content-sourcing strategy — **resolved 2026-08-23**

- [x] Choose **no bundled third-party media for v1**. This preserves the
      offline-first, no-backend scope while licensing and provenance are not
      settled.
- [x] Animated demos are out of scope for v1; no CDN/cache strategy is added.
- [x] Rule out ExerciseDB (AGPL-3.0) and Gym Visual-derived sets
      (proprietary) as sources.
- [x] Media provenance columns are not added yet because v1 imports no new
      media source. Add `media_path`, `media_attribution`, and `license_source`
      in the same migration that introduces a licensed source.
- [x] No attribution screen is required while no third-party media is bundled.

### 3D anatomy tab — **deferred by scope decision**

- [x] Reject a full 3D anatomy model for v1 because licensing and rendering
      complexity do not fit the offline tracker scope.
- [x] Defer the static SVG substitute as a separate post-v1 design task; no
      anatomy asset is bundled until the reference-library scope is approved.
- [x] The current v1 remains fully offline with no anatomy dependency.

### UI reskin — **not adopted for v1**

- [x] Keep the existing Ironyx visual language; do not adopt the amber/
      near-black Muscle & Motion reskin without a reference-library product
      decision.
- [x] Do not add media-first library rows or a dashboard media carousel while
      no licensed media source is bundled.

### Scope decision — **resolved 2026-08-23**

- [x] Ironyx remains primarily an offline workout tracker with a reference
      exercise library. A Muscle & Motion-style media/anatomy product is out of
      v1 scope and is not silently being introduced through UI polish.

## Validation checklist before release

- [x] `dart format --output=none --set-exit-if-changed .` (passes; generated output is clean.)
- [x] `dart run build_runner build` (passes; this installed build_runner no longer accepts `--delete-conflicting-outputs`.)
- [x] `flutter analyze --fatal-infos --fatal-warnings` (passes.)
- [x] `dart analyze` (passes.)
- [x] `flutter test` (green as of 2026-08-26: 337 passed, 1 skipped, 0 failed. The 6 long-standing Library/program-editor widget failures and the migration fixture failure are all fixed. Not re-run with `--coverage`; no coverage threshold is enforced anywhere.)
- [x] `flutter build apk --debug` (passes.)
- [x] `flutter build web --release` (passes.)
- [x] iOS build verified on macOS. **External validation required:** macOS/Xcode is unavailable in this Linux environment.
- [ ] Import/export failure and recovery scenarios manually tested.
- [ ] Android, iOS, Web, accessibility, and responsive checks completed.
- [ ] Final diff reviewed for unrelated changes, dead code, duplicated logic, and untested behavior.

## Audit status at creation

- Full Flutter test suite: 182 passed, 1 skipped.
- `dart analyze`: passed with no issues.
- Web release build: passed, with informational font/WASM warnings.
- Flutter analyzer: blocked in the audit environment by the read-only iOS ephemeral directory.
- Formatting check: currently reports 19 files requiring formatting.

---

# Audit 2 — production readiness review (2026-08-28)

Second full review: bugs, security, performance, reliability, architecture, code
quality, data/state, testing, and operability. Findings are ordered by real-world
impact, not by effort. `flutter analyze` was clean (0 issues) at the time of the
review, so nothing here is something the analyzer can catch for you.

Two findings were confirmed empirically with throwaway tests (deleted afterwards);
those are marked **Verified** with the observed output.

## P0 — Must fix before production

**All four items below are done as of 2026-08-28.** `flutter analyze` clean,
`dart format --set-exit-if-changed` clean, full suite green (362 passed, 1
skipped — up from the 354 baseline, net new: 2 stream-refresh tests, 5
`hasConflictingAccount` tests, 1 `accountMismatch` test, 2 account-conflict
widget tests). One new latent issue was discovered and deferred — see A2.14.

### A2.1 Drift streams go stale after every bulk write — **Fixed, verified**

**Severity:** Critical · **Category:** Bug / Data & State
**Location:** `lib/core/services/data_export_service.dart:277` (replace `DELETE`),
`:294` (insert loop), `:617-628` (`deleteAllUserData`)

Every bulk write goes through `db.customStatement(...)`, which Drift explicitly
documents as not propagating table updates
(`drift/lib/src/runtime/api/connection_user.dart:428`: *"This method does not
update stream queries on this drift database."*). Nothing in `lib/` calls
`markTablesUpdated`, `customUpdate`, or `notifyUpdates` — grep returns zero hits.

The entire read side of this app is Drift `watch()` streams
(`workoutHistoryStream`, `personalRecordWorkoutIds`, and all ~14 Progress /
Dashboard analytics providers). So after an import, snapshot restore, cloud
restore, or **Delete all data**, the database changes but every screen keeps
rendering the pre-write result set until the app is restarted.

Impact: the user taps "Delete everything", confirms by typing the word, and then
watches their workouts still sitting in their history. On cloud restore
(reinstall -> sign in -> restore) the user sees an empty app and concludes the
restore failed.

**Verified** — a `watch()` on `workoutsTable` holding one row, then
`deleteAllUserData`, then a direct `select().get()` confirming the table was
empty:

```
EMISSIONS AFTER DELETE: [1]
```

The stream never re-emitted.

- [x] Call `db.markTablesUpdated(db.allTables)` after the transaction in
      `DataExportService._applyImport`.
- [x] Call `db.markTablesUpdated(...)` after the transaction in
      `DataExportService.deleteAllUserData` (workouts, timer sessions, timer
      presets, programs, templates, body metrics, profiles + their cascaded
      children). Marks all tables rather than hand-enumerating the cascade
      graph — over-notifying is harmless, an unlisted cascaded child is not.
- [x] Verify the fix covers all four entry points: JSON import (merge and
      replace), snapshot restore, cloud restore, delete-all. All four go
      through `_applyImport`/`deleteAllUserData`, so one fix in each covers
      every caller (`applyImport`, `restoreCompleteDatabase`,
      `restoreSnapshot`, `CloudBackupController.restoreFromCloud`,
      `DataManagementSection._deleteAll`).
- [x] Add a regression test that subscribes to a `watch()` stream and asserts it
      re-emits after `deleteAllUserData` and after `applyImport`. Added to
      `test/unit/export_import_test.dart`: "a replace import notifies existing
      watch() streams" and "deleteAllUserData notifies existing watch() streams".

### A2.2 Signing out leaves the previous account's training history on the device — **Fixed**

**Severity:** High · **Category:** Security (privacy) / Data
**Location:** `lib/features/settings/presentation/widgets/account_section.dart:137`;
`lib/core/database/daos/profile_dao.dart:83`

`_signOut` calls `authController.signOut()` then `profileDao.unlinkAccount()`,
which nulls only `remoteUserId` and `email`. Workouts, body metrics, display
name, date of birth and height all remain. There is no warning on the sign-in
path either.

Two concrete failures on a shared or handed-down phone:

1. User B signs in after A signed out and sees A's full training history,
   body-weight series and personal details.
2. Worse — B taps **Back up now**. `CloudBackupController.backUpNow()` exports the
   whole local database and upserts it into B's `backups` row. A's data is now
   permanently in B's cloud slot, and RLS (correctly) will never let A retrieve
   or delete it.

The RLS policy in `docs/cloud_backup_setup.sql` is correct and does its job at the
server boundary. The leak is entirely client-side, upstream of it.

Repro: log a workout as guest or as A -> sign out -> sign in as B -> open Tracker
(A's history is there) -> Settings -> Back up now.

Resolution chosen (of the three options drafted): prompt with keep-local vs.
start-fresh, on sign-in **and** sign-up, plus a defense-in-depth guard on
`backUpNow` for the one path that has no interactive screen to prompt from.

- [x] On sign-in, compare the incoming `user.id` against the profile's existing
      `remoteUserId`. New `ProfileDao.hasConflictingAccount(String)`.
- [x] If a *different* account previously owned this profile, block silent
      adoption: prompt "This device has data from another account" with
      *keep local data* vs. *start fresh* (`deleteAllUserData` + reseed). New
      `resolveAccountConflict()` in
      `lib/features/auth/presentation/widgets/account_conflict_flow.dart`,
      wired into both `SignInPage._submit` and `SignUpPage._submit`
      (the `SignUpOutcome.signedIn` branch — `confirmationEmailSent` doesn't
      link yet, so there's nothing to check until confirmation completes).
      *Keep local data* signs back out (undoing the sign-in/up that already
      completed) rather than leaving a half-linked state.
- [x] Keep the guest -> first-account case frictionless — that is the one
      legitimate adoption path and it must not grow a dialog.
      `hasConflictingAccount` returns false for `remoteUserId == null`, so a
      guest profile links exactly as before, no dialog.
- [x] At minimum (if the full flow is deferred): require explicit confirmation
      before the first `backUpNow()` for an account whose id does not match the
      profile's `remoteUserId`. Done as defense-in-depth, not instead of the
      dialog: `app.dart`'s deep-link listener (email confirmation) has no
      reliable `BuildContext` to show the dialog from, so it now skips
      auto-linking on conflict instead of silently relinking
      (`_linkIfNoConflict`), and `CloudBackupController.backUpNow` throws a
      new `CloudBackupFailureKind.accountMismatch` if the local profile is
      still linked to a different account than the live session — this is
      what actually stops the deep-link path from uploading the wrong
      device's data, since it has no dialog to fall back on.
- [x] Add an account-switch data-isolation test. `test/unit/profile_dao_test.dart`
      (`hasConflictingAccount` group, 5 cases), `test/unit/cloud_backup_test.dart`
      ("backUpNow refuses when local data is linked to a different account"),
      `test/widget/account_section_test.dart` (two full sign-in-page flows:
      keep-local cancels and reverts; erase-and-continue wipes and relinks).
- [ ] Decide and document whether sign-out should offer "also remove local data
      from this device" — and reconcile the answer with ADR-8. Not done: this
      is a separate UX decision (proactive offer on sign-out) rather than the
      reactive conflict-detection this item was about, and didn't block closing
      the actual leak. Left open.

### A2.3 `allowBackup` defaults true; refresh token and full training DB go to Google Drive — **Fixed (Android); iOS open**

**Severity:** High · **Category:** Security
**Location:** `android/app/src/main/AndroidManifest.xml:7` (`<application>`)

`android:allowBackup` is not set, so it defaults to `true`, and there is no
`android:dataExtractionRules` (Android 12+) or `android:fullBackupContent`.
Confirmed in the package source that `supabase_flutter` 2.17.2 persists the
session via `SharedPreferencesLocalStorage`
(`supabase_flutter/lib/src/supabase.dart:131`) — **plaintext SharedPreferences
XML, not Keystore-backed secure storage**.

Android Auto Backup therefore uploads to the user's Google Drive: (a) the
long-lived Supabase refresh token, and (b) `ironyx.sqlite` containing display
name, email, date of birth, height and the complete body-weight history.
Restoring that backup onto an attacker-controlled device signed into the victim's
Google account restores a working authenticated session with no password prompt.
Health-adjacent PII crossing into third-party cloud storage is also a Play Data
Safety disclosure obligation.

- [x] Decide the policy: opt out of Auto Backup entirely, or keep it for workout
      data and exclude the credential store. Chose opt-out — the app already
      ships export files *and* cloud restore, so nothing is lost.
- [x] If opting out: set `android:allowBackup="false"` on `<application>` in
      `android/app/src/main/AndroidManifest.xml`, with a comment explaining why.
      (`android:fullBackupContent` is redundant once `allowBackup` is false and
      was left off — Android ignores it in that state.)
- [ ] If keeping it: ~~add `android:dataExtractionRules`...~~ — not applicable,
      opted out instead.
- [ ] Check the iOS equivalent — whether the app container and its
      SharedPreferences plist are eligible for iCloud/iTunes backup, and set
      `NSURLIsExcludedFromBackupKey` where appropriate. **Still open.** This
      needs native Swift/Obj-C changes in `ios/Runner/`, and this environment
      has no Xcode to build or verify them against (same limitation the
      "Validation checklist" section already notes for the iOS build). Do this
      on macOS before an iOS release.
- [ ] Update the Play Data Safety declaration to match whatever is decided.
      Still open — a Play Console task, not a code change.

### A2.4 No global error handling and no crash reporting anywhere — **Hooks fixed; reporter backend still open**

**Severity:** High · **Category:** Reliability / Production readiness
**Location:** `lib/main.dart`

Grepping `lib/` for `FlutterError.onError`, `PlatformDispatcher.instance.onError`,
`runZonedGuarded`, `ErrorWidget.builder`, Crashlytics and Sentry returns
**nothing**. The only reporting call in the app is the `FlutterError.reportError`
inside `_initSupabase`'s catch.

In release, an uncaught async error is swallowed silently and a build error paints
the grey/red error screen with no record kept. There is zero visibility into what
breaks on testers' devices — no crash rate, no stack traces, and no way to have
learned about A2.1 from the field. There are also unguarded async call sites, e.g.
`workout_xlsx_import_action.dart:65` calls `WorkoutXlsxImportService.apply(...)`
with no try/catch, so an FK or UNIQUE failure mid-import becomes an unhandled
exception raised from a tap handler.

Decision made when applying this: wire the hooks through one seam now
(`reportError()`), defer the actual crash-reporter backend since provisioning
one (Sentry account, DSN, dependency) is an external-service decision, not
something to make unilaterally while fixing a bug list.

- [x] Set `FlutterError.onError` in `main()` (present the error, then forward).
      New `lib/core/error_reporting.dart`'s `reportError()` is the one seam
      every hook below funnels through; wiring a real backend later touches
      only that one function.
- [x] Set `PlatformDispatcher.instance.onError` in `main()`.
- [x] Set `ErrorWidget.builder` to render the existing `core/widgets/error_view.dart`
      instead of the default red screen. Wrapped in `Directionality` +
      `Material` (this can replace a widget above `MaterialApp` itself, so
      neither ancestor is guaranteed), and passes `title` explicitly rather
      than `ErrorView`'s l10n-reading default — the fallback for "everything
      else already failed" cannot itself depend on `Localizations` being
      mounted.
- [x] Wrap `WorkoutXlsxImportService.apply(...)` at
      `workout_xlsx_import_action.dart:65` in a try/catch with a user-facing
      message. New `importXlsxApplyFailed` l10n string (en + ar), generic
      rather than raw-exception (didn't want to add a fourth instance of the
      A2.9 anti-pattern while it's still open).
- [ ] Choose and wire a crash reporter. Given ADR-8's offline-first posture,
      Sentry with `beforeSend` scrubbing (or a self-hosted endpoint) fits better
      than Crashlytics' Firebase dependency. **Still open** — needs a service
      decision (see above); `reportError()` is the integration point when
      that's made.
- [x] Ensure the reporter never transmits an email address — `AuthException`
      messages can carry one, which is why `SupabaseAuthService._log` is already
      `kDebugMode`-gated. `reportError()` follows the same rule: it's a no-op
      outside `kDebugMode` until a real backend is wired in, at which point
      whatever's wired in inherits that gate for free.

## P1 — Recommended before wider release

**All six items below are done as of 2026-08-29.** `flutter analyze` clean,
`dart format --set-exit-if-changed` clean on every touched file. One item
(A2.5's size-ceiling sub-item) was implemented as a soft log rather than a
hard limit — see that item for why.

### A2.5 Whole-database serialization runs synchronously on the UI isolate — **Fixed**

**Severity:** Medium · **Category:** Performance
**Location:** `lib/core/services/data_export_service.dart:87`
(`JsonEncoder.withIndent('  ')`);
`lib/features/backup/data/supabase_cloud_backup_service.dart:61`
(`gzip.encode` + `base64Encode`)

`buildJsonExport` reads every table into memory then runs a synchronous,
non-yielding encode over the full dataset. `upload` adds a synchronous gzip and
base64 over the same buffer. All on the main isolate.

This runs on three paths, one of them invisible to the user: manual export, **every
cloud backup**, and **the pre-import snapshot taken before every import/restore**
(`data_export_service.dart:243`). The code comments cite ~1.4 MB of JSON for a year
of training, and `withIndent` roughly doubles that. On a mid-range Android phone
that is hundreds of milliseconds to seconds of frozen UI with no frames — long
enough to risk an ANR on the import path, where it happens behind a spinner the
user reads as progress.

- [x] Move the JSON encode off the main isolate with `Isolate.run` (keep the DB
      reads on the main isolate — Drift needs its executor). Used `compute()`
      instead of raw `Isolate.run` — browsers have no isolate primitive at all,
      and `compute` is Flutter's own cross-platform-safe wrapper: a real
      background isolate on native platforms, running inline in place on web
      rather than failing there. `buildJsonExport` now reads all tables inside
      `db.transaction`, then hands the plain data (no `AppDatabase` reference —
      that can't cross an isolate boundary) to a new top-level
      `_encodeExportEnvelope` via `compute`.
- [x] Move gzip + base64 in `SupabaseCloudBackupService.upload` off the main
      isolate too. Same pattern: new top-level `_gzipAndBase64Encode`, called
      through `compute`.
- [x] Drop `withIndent` for the cloud payload specifically — nobody reads it, and
      it halves the bytes before compression. `buildJsonExport` gained an
      `indent` parameter (default `true`, preserving the file-export and
      snapshot behavior); `CloudBackupController.backUpNow` passes
      `indent: false`.
- [x] Consider a size ceiling / warning for very large exports. Implemented as
      a non-blocking log rather than a hard ceiling — a large export is still
      a valid one, and blocking it would be user-hostile for no real benefit.
      `buildJsonExport` calls `reportError` (A2.4's seam) if the encoded
      payload exceeds 20MB (~14x the "a year of hard training" reference point
      in the code comments), so it's visible in telemetry once a reporter
      exists, without ever refusing the export itself.

**Web build caveat:** `flutter build web --release` could not be run to
completion in this environment to directly confirm `compute()` compiles clean
end-to-end — it was still compiling after 30 minutes when the attempt was
killed, which appears to be this sandbox being slow rather than a real error
(no error was printed; a prior successful web build artifact from 2026-08-23
already exists in `build/web/`, well before this change). `compute()` is
Flutter's documented, widely-used solution specifically for this
native-isolate/no-isolate-on-web split, so this isn't considered a real risk
— but a real `flutter build web --release` on faster hardware is worth
running once, purely for confirmation, before this ships.

### A2.6 First-launch seed: ~2,400 individually-committed statements, no transaction — **Fixed**

**Severity:** Medium · **Category:** Performance / Reliability
**Location:** `lib/core/services/exercise_seeder.dart:56` (`_seedDatabase`)

The loop runs one `upsertExercises` plus seven `replaceX` calls per exercise, and
none of it is wrapped in `db.transaction`. With ~301 exercises that is ~2,400
statement groups, each an implicit transaction with its own fsync.

`allExercisesStream`, `exercisesSearchStream`, `exercisesFilteredStream` and
`exerciseDetail` all `await ref.watch(exerciseSeederProvider.future)`, so Library
and parts of Dashboard are gated on this — during the user's very first launch, on
the slowest storage path. An interrupted seed also leaves the catalogue partially
populated; the `seededCount >= exercises.length` guard recovers, but only by
redoing all of it.

- [x] Wrap the `_seedDatabase` body in `db.transaction(() async { ... })`. Single
      commit instead of ~2,400; also makes the seed atomic, removing the
      partial-seed state entirely.
- [x] Measure cold-start-to-Library before and after, and record the numbers here.
      **Inconclusive in this environment, honestly reported:** timed via
      `Stopwatch` around `exerciseSeederProvider.future` on
      `AppDatabase.forTesting()` — 4367ms before, 4311ms after, i.e. no
      measurable difference. This is very likely because
      `AppDatabase.forTesting()` uses an in-memory sqlite database, which has
      no per-statement disk fsync cost — exactly the cost this fix removes.
      The in-memory test executor can't exercise the bottleneck it's meant to
      fix. The transaction wrap is still correct (atomicity alone justifies
      it — see the previous paragraph), but the real-world speedup on a
      file-backed database on an actual device remains unmeasured. Whoever
      picks this up next should time a real on-device cold start (or a
      file-backed sqlite3 database in a benchmark, not `forTesting()`) rather
      than trust this number.

### A2.7 XLSX import aborts on any workbook containing an empty sheet — **Fixed, verified**

**Severity:** Medium · **Category:** Bug
**Location:** `lib/core/services/workout_xlsx_import_service.dart:33`

`_dateValue(_rowCell(rows[0], groupStart))` indexes `rows[0]` unconditionally.
`_rowCell` guards its *column* index but nothing guards the *row* index, and
`sheet.rows` is `[]` for a sheet with no data.

**Verified** — a default `Excel.createExcel()` workbook has one sheet with zero
rows:

```
SHEETS: [Sheet1]  rows=[0]
RangeError (length): Invalid value: Valid value range is empty: 0
  package:ironyx/core/services/workout_xlsx_import_service.dart 33:46
```

It is caught at `workout_xlsx_import_action.dart:52`, so it does not crash — but
the entire import is abandoned including every valid sheet in the workbook, and
the user is shown the literal string
`RangeError (length): Invalid value: Valid value range is empty: 0`. Blank
trailing sheets are extremely common in real spreadsheets.

- [x] Skip sheets with too few rows: `if (rows.length < 3) continue;` (needs a
      header row plus data rows) before touching `rows[0]`.
- [x] Add a test for a workbook with an empty sheet alongside a populated one,
      asserting the populated sheet still imports.
      `test/unit/workout_xlsx_import_service_test.dart`: "a blank trailing
      sheet does not abort the import of a populated one" — builds a sheet via
      `excel['Blank Tab']` (auto-created with zero rows) alongside the normal
      populated sheet, and asserts the populated one still parses.
- [x] Replace the raw-exception message with an actionable one (see A2.9,
      which did this for all four raw-exception sites at once).

### A2.8 Import progress dialog is escapable, and dismissing it pops the Settings page — **Fixed**

**Severity:** Medium · **Category:** Bug
**Location:** `lib/features/settings/presentation/widgets/data_management_section.dart:240`,
`:255`, `:260`

`barrierDismissible: false` blocks tap-outside but **not** the Android system back
button, and the dialog is not wrapped in `PopScope`. Because `_runImport` is
`unawaited`, backing out of the spinner leaves the import running; on completion
`Navigator.of(context, rootNavigator: true).pop()` fires against a root navigator
whose top route is now the Settings page — so it pops Settings instead of the
already-gone dialog.

Repro: Settings -> Import -> confirm -> press the system back button while the
spinner is up -> wait for the import to finish. Settings closes itself.

- [x] Wrap the progress dialog's child in `PopScope(canPop: false, ...)`.
- [x] Hold the dialog's own route reference (or a `GlobalKey`) and pop that,
      rather than popping the root navigator blind — both at `:255` and `:260`.
      Captured a `BuildContext?` from the dialog's own `builder` (a
      `progressContext` local) and pop `Navigator.of(progressContext)`, guarded
      by `progressContext.mounted` — checked at close time rather than the
      outer Settings context's `mounted`, which stays true regardless of what
      happens to the dialog on top of it and so can't answer "is the dialog
      still there to close."
- [x] Add a widget test that presses back during an in-flight import and asserts
      Settings is still on screen.
      `test/widget/settings_page_test.dart`, new `import progress dialog`
      group. Reproduces the exact dialog shape (`PopScope(canPop: false)` +
      context captured from `builder`) standalone rather than driving it
      through `DataManagementSection._runImport` itself — that path starts
      with `FilePicker.pickFile()`, which has no test-time platform channel
      and no mockable seam anywhere in this codebase (see A2.10 and A2.14 for
      the same recurring gap). Uses `tester.binding.handlePopRoute()`, the
      standard way flutter_test simulates the Android system back button.

### A2.9 Raw exception text is shown to end users — **Fixed**

**Severity:** Low · **Category:** Code quality / UX
**Location:** `active_workout_page.dart:192`, `data_management_section.dart:225`
and `:261`, `workout_xlsx_import_action.dart:55`

`activeWorkoutSaveFailed('$error')`, `dataSnapshotRestoreFailed('$e')`,
`dataImportFailed('$e')` and `importXlsxReadFailed('$error')` interpolate
`toString()` of arbitrary exceptions into a `SnackBar` or dialog. SQLite errors
can echo column values back into the UI.

This is inconsistent with the care taken elsewhere: `CloudBackupFailure` and
`AuthFailure` both deliberately keep `detail` for logs and route the user-facing
string through `messageFor(l10n)`.

- [x] Give each of the four sites a localized, actionable message. All four
      l10n keys (`activeWorkoutSaveFailed`, `dataSnapshotRestoreFailed`,
      `dataImportFailed`, `importXlsxReadFailed`) dropped their `{error}`
      placeholder for a plain, generic, actionable string (en + ar), e.g.
      "Couldn't save your workout. Your sets are still here — try again." —
      each states what's still safe (nothing was written / your data is
      untouched) rather than echoing the exception.
- [x] Send the raw text to the reporter from A2.4 instead of to the screen.
      All four catch sites now call `reportError(error, stackTrace, context:
      '...')` before showing the generic message.
- [ ] Consider a shared failure-kind enum for import/export, mirroring
      `CloudBackupFailureKind`. **Not done, deliberately.** All four sites are
      blanket `catch (e)`/`on Object catch (error)` with no typed exception
      hierarchy underneath them (unlike Auth/CloudBackup, which have real
      Supabase exception types to discriminate on) — an enum here would have
      exactly one meaningful value (`unknown`) at every site, which isn't
      worth the ceremony. Revisit if these call sites ever grow real,
      distinguishable failure modes worth telling apart in the UI.

### A2.10 Testing gaps that let the above ship — **Mostly closed**

**Severity:** Medium · **Category:** Testing

- [x] Stream-refresh assertion after import and delete-all (would have caught
      A2.1 — see that item). Closed when A2.1 was fixed.
- [x] XLSX workbook with an empty / extra sheet (would have caught A2.7).
      Closed when A2.7 was fixed.
- [x] Account-switch data isolation (would have caught A2.2). Closed when
      A2.2 was fixed.
- [ ] A test that a failing `WorkoutXlsxImportService.apply` surfaces a message
      rather than an unhandled exception (A2.4). **Still open, and likely to
      stay open without more work than this item is worth on its own.** The
      try/catch itself was added when A2.4 was fixed
      (`workout_xlsx_import_action.dart`), but reaching it in a test means
      driving through `WorkoutXlsxImportAction._run`, which opens with
      `FilePicker.pickFile()` — no test-time platform channel, no mockable
      seam anywhere in this codebase (same blocker noted for A2.8 and A2.14).
      A real fix here is introducing a `FilePicker`-abstraction seam used by
      all three call sites that touch it
      (`workout_xlsx_import_action.dart`, `program_import_action.dart`,
      `data_management_section.dart`) — worth doing once, not as a one-off
      for this single test.
- [x] Back-button-during-import widget test (A2.8). Closed when A2.8 was
      fixed — see that item for why it's a standalone reproduction rather
      than a test of `DataManagementSection` itself (same `FilePicker` seam
      gap as above).

## P2 — Nice to have

### A2.11 Release-build hygiene — **Log-guarding fixed; ProGuard deliberately left alone**

**Severity:** Low · **Category:** Production readiness

- [x] `lib/core/router/app_router.dart:40` — `debugLogDiagnostics: true` is
      unconditional. go_router logs via `dart:developer`, which is **not** stripped
      in release, so every navigation is written to logcat in production. Change
      to `debugLogDiagnostics: kDebugMode`.
- [x] `lib/main.dart:45` — `debugPrint('[auth] Supabase URL: ...')` is unguarded.
      `SupabaseAuthService._log` gets this right with its `kDebugMode` check;
      match it. (`main.dart:38` and `:54` too.) All three now check `kDebugMode`
      before printing.
- [ ] `android/app/build.gradle.kts` release block sets no `isMinifyEnabled` /
      `isShrinkResources`. Not a vulnerability, but it costs APK size and free
      symbol obfuscation. Consider enabling with the Flutter default ProGuard
      rules. **Deliberately not done.** CI only ever builds the debug APK
      (`flutter build apk --debug`); nothing in this repo builds or smoke-tests
      the *release* variant, so turning on shrinking here would be unverified —
      if a plugin needs a keep rule this doesn't have, it would only surface as
      a runtime crash on a real device, at release-cut time, with nothing in
      CI to have caught it first. That's a worse failure mode than the current
      one (a slightly larger APK). Enable this alongside actually running a
      release build on a real device before flipping it.
- [ ] Add `--obfuscate --split-debug-info=...` to the release build command, and
      decide where symbol files are archived (needed to symbolicate A2.4's crash
      reports). Left open for the same reason — meaningful only once a real
      crash reporter (A2.4) and a tested release build pipeline both exist to
      consume the symbol files; adding the flag alone with nowhere to archive
      the output doesn't accomplish anything yet.

### A2.12 `_isValidIdentifier` does not validate what its error message claims — **Fixed**

**Severity:** Low · **Category:** Code quality
**Location:** `lib/core/services/data_export_service.dart:590`

The second branch, `RegExp(r'^[A-Za-z0-9_]+$')`, accepts any alphanumeric string,
making the UUID regex below it unreachable for practically every input, and the
error message *"must contain a valid UUID or legacy identifier"* misleading during
debugging. There is **no injection risk** — all values are bound as parameters and
table/column names come from `db.allTables` — so this is purely about the check
meaning what it says.

- [x] Either narrow the branch to the specific legacy id shapes that need
      grandfathering, or rename the method and soften the message to match what it
      actually enforces. Chose the rename: narrowing to an exact enumerated set of
      legacy shapes (`ex_NNN`, single lowercase words for muscles/equipment,
      `builtin_*`, the two sentinels) would tightly couple validation to
      today's seed content and break the moment a new id shape is added.
      Renamed `_isValidIdentifier` to `_hasSafeIdentifierShape` and reworded
      both call-site messages to "must be a UUID or a plain alphanumeric
      identifier" — accurate to what the check actually does, with a doc
      comment on the method spelling out that this is a shape check, not a
      lookup against known ids.

### A2.13 Smaller cleanups — **3 of 4 done**

- [ ] `WorkoutXlsxImportService._isDuplicateOfExisting` issues a query per
      workout, plus per exercise, plus per set group, outside a transaction. Fine
      at current scale; batch it if workbooks grow. **Deliberately left as-is** —
      this item's own text already says it's not a current problem, and batching
      would mean restructuring the duplicate-detection algorithm from
      one-workout-at-a-time to a bulk prefetch, which is real scope for zero
      observed benefit today. Revisit if workbook sizes actually grow.
- [x] `data_export_service.dart:277` and `:294` interpolate `$tableName`
      unquoted into `DELETE FROM` / `INSERT INTO`, while the same file quotes
      identifiers everywhere else. Names come from `db.allTables` so it is safe
      today — make it consistent anyway. Both now go through
      `_quoteIdentifier`.
- [x] `WorkoutXlsxImportService._normalize` strips all non-`[a-z0-9]` characters,
      so a non-Latin (e.g. Arabic) exercise name normalizes to the empty string
      and produces a meaningless slug like `-imported-a1b2c3d4`. Harmless today
      (the catalogue is English-named; Arabic is translate-at-display), but worth
      a fallback. The custom-exercise slug builder now falls back to the literal
      prefix `exercise` when normalization empties out, so the slug reads
      `exercise-imported-a1b2c3d4` instead. New test: "a non-Latin exercise name
      still gets a sane slug when created as custom" (uses an Arabic name).
- [x] `TimerController._finish` returns early on `_disposed` after awaiting
      `_wakelock.disable()`, skipping `_writeSession` — a completed timer session
      would go unrecorded. Unlikely given `keepAlive`, but the early return is on
      the wrong side of the write. Fixed by reading the `TimerDao` up front
      (before any await) and passing it into `_writeSession` as a parameter, so
      the DB write no longer touches `ref` at all and cannot be skipped by a
      disposal race — regardless of ordering, once `_finish()` starts, the
      session gets written.
      **Also found and fixed while writing the regression test, not by
      inspection:** the class's own `_disposed` bool (set from an `onDispose`
      callback) is not reliably synchronized with Riverpod's actual ref-validity
      state — a test that disposed the container mid-`_finish()` crashed with
      "Cannot use the Ref... after it has been disposed" at *both* the
      haptics/sound block and the final `state = null`, despite each being
      guarded by `if (!_disposed)`/`if (_disposed) return`. Riverpod's own
      `ref.mounted` getter is the authoritative, always-current signal (its own
      exception message says as much); both sites now check `ref.mounted`
      instead. New test in `test/unit/timer_controller_test.dart`: "a session
      completed right as the controller is disposed is still written" —
      disposes the container while `_finish()` is suspended awaiting
      `_wakelock.disable()`, then asserts the session row still exists. This
      test failed twice before passing, against two different lines, before
      landing on `ref.mounted` — the other ~9 `_disposed` checks elsewhere in
      this class were not audited and may have the same latent issue; this fix
      only touched the two inside `_finish()`.

### A2.14 `programSeederProvider` may run `build()` twice when invalidated while ambiently watched — **not reproducible against the real flow; documented and tested instead**

**Severity:** Low (downgraded from Medium — a follow-up real end-to-end test
of the actual Settings flow did not reproduce it across 4 runs; see the
checklist below) · **Category:** Reliability / Concurrency
**Location:** `lib/core/services/program_seeder.dart` (`ProgramSeeder.build`),
triggered by the `resetSeedVersion()` -> `ref.invalidate(programSeederProvider)`
-> `await ref.read(programSeederProvider.future)` sequence, while
`app.dart`'s `IronyxApp.build()` also holds an ambient
`ref.watch(programSeederProvider)`.

Found while adding the A2.2 widget test for the "erase local data and
continue" path, which calls exactly this sequence (mirroring the pre-existing,
already-shipped `DataManagementSection._deleteAll` flow — this is not new
code, just newly exercised). Debug instrumentation showed `build()` starting
twice for one invalidation; one invocation ran to completion and inserted all
three built-in programs, but the *other* stayed stuck partway through
`dao.insertProgram('builtin_full_body', ...)` and never resolved. Whichever
copy `programSeederProvider.future` ends up pointing to determines whether the
caller's `await` ever returns — in the reproduction, it pointed at the stuck
one, hanging the caller indefinitely.

No production repro yet — this was only ever hit via a widget test's
`tester.pump()`/`runAsync` interleaving, and it's possible real Flutter frame
scheduling never creates the same race. But `DataManagementSection._deleteAll`
(Settings -> Delete all data) has run this *exact* sequence since it shipped,
and — confirmed by re-reading `test/widget/settings_page_test.dart` — no
existing test ever taps through to the real confirm button, so this path has
never actually been exercised end-to-end by the suite either. Given that, the
honest state is "untested," not "known safe."

The account-conflict widget test for this path now uses `stubSeeders()`
(`test/helpers/stub_seeders.dart`, already used elsewhere in the suite for
this exact class of problem) to route around it rather than fix it — fixing a
Riverpod invalidation race in shared seeder infrastructure was out of scope
for the four P0 items this session was applying, and touching it blind
without being able to reproduce it outside a test harness risked a worse bug
than the one being chased.

- [x] Try to reproduce outside a widget test — a real device/simulator run of
      Settings -> Delete all data, watched for a hang or a duplicate-row error
      in built-in programs. **No real device available in this environment**,
      so this was approximated instead with the next item: a real (not
      stubbed) *widget* test of the exact same button, which is the closest
      available substitute and the thing A2.14 itself flagged as the actual
      test-coverage gap. It passed cleanly, 4 runs in a row (no hang, no
      duplicate-row error, programs correctly present both before and after).
      A true on-device run is still the more authoritative check and remains
      open — but a widget test exercising the identical provider sequence
      failing to reproduce it across repeated runs is meaningful evidence
      this is a test-harness artifact of the *account-conflict* test's
      specific pump/`runAsync` interleaving, not a bug reachable from the
      real Settings flow.
- [ ] If reproducible: the likely fix is not calling `ref.invalidate` +
      immediate `ref.read(...future)` on a provider that's also watched
      elsewhere in the same synchronous frame — e.g. read the notifier once,
      call a plain method on it that does the reset-and-reseed work directly
      (bypassing `build()`/`invalidate` entirely for this one operation),
      rather than relying on Riverpod's rebuild machinery to do it exactly
      once. **Not attempted** — did not reproduce, so there is nothing
      concrete to fix, and changing shared seeder infrastructure without a
      failing case to verify against would be a guess, not a fix.
- [x] If not reproducible outside tests: add a code comment at both call sites
      (`account_conflict_flow.dart` and `data_management_section.dart`)
      documenting the risk and pointing here, and add a real (not stubbed)
      end-to-end test for `DataManagementSection`'s "Delete all data" confirm
      button — the gap that let this go unnoticed since the feature shipped.
      Both done: a comment at each call site cross-references the other and
      points here, and `test/widget/settings_page_test.dart` gained "tapping
      Delete everything actually deletes data and reseeds built-in
      programs" — no `stubSeeders()`, real exercise/program seeding on boot
      (`awaitDatabase: true`), taps the real confirm button, and asserts
      programs exist both before (proving the seeders actually ran) and
      after (proving delete + reseed completed) the real delete-all flow.

**Update, same session — root cause found, not the seeder race:** this new
test failed once under the full 366-test suite's load after passing 4/4 in
isolation, with a fixed `Duration(seconds: 1)` wait after the delete-all tap.
A second full-suite run (this time with untruncated output) caught it
failing again, but at a *different, earlier* assertion — `programsBefore`,
checked right after the initial `pumpApp(..., awaitDatabase: true)`, before
delete-all is ever tapped. `pumpApp`'s own `awaitDatabase` option only waits
a fixed 100ms for real sqlite3 seeding to finish; under the full suite's
concurrent load, seeding ~301 exercises and 3 programs didn't finish in that
window. This conclusively points to "fixed waits too short under load" as
the actual cause of both flakes, not the `programSeederProvider` double-build
race this item is about — the second failure happened before delete-all (and
therefore before any invalidate/reseed) was even triggered.

Both fixed waits (initial seed, post-delete-all reseed) were replaced with
one shared polling helper (up to 50 x 200ms = 10s, checking the program
count after each), which adapts to actual system load instead of assuming a
duration — but a *third* full-suite run still failed at the same
`programsBefore` check even with the 10-second polling ceiling in place,
which is a strong signal the real ~301-exercise seed (not the program
seeder this item is about) can genuinely take longer than that under this
particular full-suite's load, in this sandboxed environment specifically —
not evidence of a hang.

The actual fix: this test does not need the real exercise seeder at all —
only `ProgramSeeder`'s real reset/invalidate/reseed sequence is what A2.14
is about. `exerciseSeederProvider` is now overridden with a local
`_NoopExerciseSeeder`, and the handful of exercise ids the three built-in
programs actually reference (18 ids, checked via
`grep -oE "'ex_[0-9]+'" program_seeder.dart`) are seeded directly instead —
lightweight, deterministic, and no longer coupled to the unrelated
exercise-catalogue seeder's performance under load. The real `ProgramSeeder`
still runs unstubbed, so the actual sequence under test is untouched.
Re-verified 3x in isolation (now ~3s each, down from ~6-8s) and once against
the full suite (367 passed, 1 skipped, 0 failed) — clean.

## Confirmed working — do not "fix"

Recorded so a later pass does not burn time re-deriving these.

- **The import validator is genuinely thorough.** Schema-version match, exact
  table-set match, unknown-table rejection, mandatory user-data tables on replace,
  per-column type/nullability derived live from `PRAGMA table_info`, primary-key
  uniqueness, and full foreign-key resolution — all before a single row is
  touched, followed by an automatic pre-import snapshot with retention.
- **The RLS policy is correct.** `for all ... using (auth.uid() = user_id) with
  check (auth.uid() = user_id)` — the `WITH CHECK` half does stop a client
  rewriting `user_id` on the way in, as its comment claims.
- **Secrets hygiene is clean.** `supabase.json` is gitignored and confirmed
  untracked; only `supabase.example.json` is committed; keystore and
  `key.properties` are gitignored; the key in use is a `sb_publishable_` key,
  public by design.
- **Deep-link design is right.** Namespacing the scheme to the bundle id rather
  than a squattable `ironyx://` is correct; PKCE is `supabase_flutter`'s default
  for this flow.
- **`TimerEngine`** recomputing from wall clock rather than accumulating ticks is
  the correct architecture for a backgroundable timer, and is cleanly testable via
  the injected `clock`.
- **`ActiveWorkoutNotifier._writeQueue`** — serializing SharedPreferences writes,
  and reading `state` *inside* the queued closure rather than at call time, is a
  subtle ordering bug most codebases ship with.
- **Vendor seams hold.** No Supabase type escapes `SupabaseAuthService` or
  `SupabaseCloudBackupService` into any controller or widget.
- **CI is thorough**: format, `analyze --fatal-infos --fatal-warnings`, asset
  licence gate, tests with coverage, Android + web builds. Analyzer config is
  strict (`strict-casts`, `strict-inference`, `strict-raw-types`,
  `avoid_dynamic_calls`, `use_build_context_synchronously`).

## Open questions — need input, not assumptions

- [ ] Current `docs/ADR.md` and PLAN.md Phase 5 sync design — does the temporary
      backup slot create migration debt for real per-table sync?
- [ ] Target `minSdk` / `targetSdk` (both resolve from `flutter.*` at build time),
      needed to judge A2.3's Auto Backup behaviour precisely.
- [ ] Does the Supabase project have email confirmation and rate limiting enabled
      server-side? The client maps `over_email_send_rate_limit`, but that is not
      evidence the server enforces it.

## Audit 2 status at creation

- `flutter analyze`: **0 issues** (15.4s).
- Full test suite: **not re-run** during this review (per the standing note about
  long-running test commands). Last recorded green run: 2026-08-26, 337 passed,
  1 skipped.
- Two findings verified with throwaway tests, since deleted: A2.1
  (stream staleness) and A2.7 (XLSX empty sheet).
- **Production-readiness rating: 6 / 10.** The architecture is well above average
  — ADR-driven, clean vendor seams, an import validator more rigorous than most
  commercial apps ship, comments that explain *why*. What holds the score down is
  the gap between that design quality and operational readiness: a correct,
  well-tested data layer paired with a UI that silently does not refresh after the
  most destructive operations (A2.1), a real cross-account privacy leak the
  server-side RLS cannot help with (A2.2), and no crash reporting to have learned
  about either from the field (A2.4). None of the four P0s are architectural —
  they are a missing `markTablesUpdated`, a missing account-identity check, a
  missing manifest attribute, and a missing error handler. Roughly a day of work,
  and it would put this at an 8.

## Update — 2026-08-28, P0 applied

All four P0 items above are done (A2.3 and A2.4 each have one sub-item —
iOS backup exclusion, the crash-reporter backend — correctly left open, since
neither is something to complete from this environment or unilaterally).
`flutter analyze`: 0 issues. `dart format --set-exit-if-changed`: clean on
every touched file. Full suite: 362 passed, 1 skipped (was 337 at last
recorded green run, 354 immediately before this session's test additions).

One new issue was found in the process of testing A2.2 properly, not
introduced by it: A2.14, a latent double-invocation race in
`programSeederProvider` triggered by invalidating it while it's also
ambiently watched (`app.dart`). It affects the already-shipped Settings
"Delete all data" flow too — that flow has apparently never been tested
through to its real confirm button — so this is a pre-existing gap this
session's testing surfaced, not a regression. Deferred rather than fixed
blind; see A2.14 for the reproduction and the suggested next step.

## Update — 2026-08-29, P1 applied

All six P1 items are done. `flutter analyze`: 0 issues. `dart format
--set-exit-if-changed`: clean on every touched file. Full suite: 364 passed,
1 skipped (net +2 over the 362 baseline after P0: the A2.7 blank-sheet test
and the A2.8 back-button test; A2.5/A2.6/A2.9 changed behavior covered by
existing tests rather than adding new ones, and A2.10's remaining gap was
left honestly open rather than filled with a low-value test — see below).

Two things surfaced worth flagging rather than quietly absorbing:

- **A recurring test-infrastructure gap, not a defect in the fixes
  themselves:** three separate P1/P0 items (A2.8's back-button test, A2.10's
  still-open `apply()`-failure test, and by extension anything else that
  starts with a file picker) are all blocked by the same thing —
  `FilePicker.pickFile`/`saveFile` has no test-time platform channel and no
  mockable seam anywhere in this codebase. A2.8's test worked around it by
  reproducing the dialog mechanism standalone; A2.10's could not be worked
  around the same way and was left open rather than forced. The real fix is
  a `FilePicker` abstraction seam shared by the three call sites that use it
  (`workout_xlsx_import_action.dart`, `program_import_action.dart`,
  `data_management_section.dart`) — worth doing once as its own piece of
  work, not as a one-off for a single test.
- **A2.5's cold-start timing measurement came back inconclusive**, and says
  so rather than reporting a number that would look precise but isn't:
  `AppDatabase.forTesting()`'s in-memory database has no per-statement fsync
  cost, which is exactly what the transaction wrap removes, so the test
  environment can't observe the fix's real-world effect. The fix is still
  correct (atomicity alone justifies it), but the performance claim needs a
  real device or a file-backed benchmark to actually verify — flagged in
  A2.5 rather than left silently unconfirmed.
- **The web build could not be run to completion in this environment**
  (killed after 30 minutes, still mid-compile, no error printed) to directly
  confirm `compute()` — used in place of `Isolate.run` for A2.5's isolate
  offloading, since raw isolates don't exist on the web target — compiles
  clean end-to-end. `compute()` is Flutter's own documented cross-platform
  answer to exactly this, so this isn't treated as a real risk, but a real
  `flutter build web --release` on faster hardware is worth running once for
  confirmation before shipping.

## Update — 2026-08-29, P2 applied

All four P2 items addressed; three fully, one (A2.14) resolved by
downgrading rather than fixing blind — see below. `flutter analyze`: 0
issues. `dart format --set-exit-if-changed`: clean on every touched file.
Full suite: see the test-count note at the end of this update.

- **A2.11**: the two log-guarding sub-items are done
  (`debugLogDiagnostics: kDebugMode`, all three `main.dart` `debugPrint`s
  gated). The ProGuard/minification sub-items were deliberately *not*
  done: CI never builds or tests the release APK variant, so flipping
  `isMinifyEnabled` here would be an unverified change to a build type
  nothing exercises — if a plugin needed a keep rule this doesn't have, it
  would only surface as a runtime crash on a real device at release-cut
  time. Left open with that reasoning attached, rather than guessed at.
- **A2.12**: renamed `_isValidIdentifier` to `_hasSafeIdentifierShape` and
  reworded both call sites' messages, rather than narrowing the regex —
  narrowing would tightly couple the check to today's exact seed-id shapes.
- **A2.13**: 3 of 4 sub-items fixed (quoting, non-Latin slug fallback,
  `TimerController._finish`). The query-batching item was left alone per
  its own "fine at current scale" framing. The `TimerController` fix
  surfaced a second, related bug while writing its regression test — the
  class's own `_disposed` bool is not reliably synchronized with Riverpod's
  actual ref-validity state, and two `ref`-touching sites inside `_finish()`
  crashed under a real disposal race despite being guarded by it. Both
  switched to `ref.mounted`, Riverpod's own authoritative signal. Worth
  noting: the other ~9 `_disposed` checks elsewhere in `TimerController`
  were not audited and may have the same latent issue — only the two inside
  `_finish()` were touched.
- **A2.14**: attempted the reproduction the item asked for — a real,
  unstubbed end-to-end widget test of the actual Settings "Delete all data"
  button (no on-device run was available in this environment) — and the
  `programSeederProvider` race itself did not reproduce. Downgraded from
  Medium to Low, documented with cross-referencing comments at both call
  sites, and kept the new test as permanent coverage of a button that, per
  A2.14's own investigation, had never actually been tapped by any test
  since it shipped.
  **This new test then went through three rounds of its own flakiness**
  before landing — worth recording in full since it's a real example of the
  "don't trust a single green run" principle: fixed-duration waits on real
  sqlite3 seeding work passed reliably alone but failed intermittently under
  the full 366+-test suite's load, twice, at two different assertions, each
  time looking superficially like it might be A2.14's actual race. Chasing
  the *actual* error text (not just the failure) both times showed neither
  was the race — both were the unrelated, real ~300-exercise catalogue
  seeder simply not finishing inside a fixed window under load. The test
  now stubs the exercise seeder (irrelevant to what it's checking) and
  seeds by hand only the 18 exercise ids the three built-in programs
  reference, while leaving the real `ProgramSeeder` — the thing actually
  under test — untouched. Confirmed clean across 3 isolated runs and one
  full-suite run (367 passed, 1 skipped, 0 failed).

Net new tests this pass: `workout_xlsx_import_service_test.dart`'s Arabic-slug
case, `timer_controller_test.dart`'s disposal-race case, and
`settings_page_test.dart`'s real delete-all case — 3 total. Final verified
full-suite result: **367 passed, 1 skipped, 0 failed.**
