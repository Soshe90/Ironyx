# FitTrack TODO

This checklist captures the production-hardening work identified during the architecture, data-integrity, UX, and release-readiness audit. Prioritize data safety before polish.

## Priority 0 — Backup and data-integrity safety

### Import envelope validation

- [ ] Require all ADR-7 envelope fields during parsing:
  - [ ] `formatVersion`
  - [ ] `dbSchemaVersion`
  - [ ] `appVersion`
  - [ ] `exportedAt`
  - [ ] `tables`
- [ ] Reject missing, malformed, or invalid `exportedAt` values instead of substituting the Unix epoch.
- [ ] Reject unknown table names.
- [ ] Define and validate the complete expected table set for a full export.
- [ ] Validate each imported row's column names and required fields before touching the database.
- [ ] Validate row value types before SQL insertion.
- [ ] Validate UUIDs and foreign-key relationships before applying an import.
- [ ] Ensure the preview reports that the file is incomplete or partial when applicable.
- [ ] Add tests for malformed headers, missing fields, unknown tables, invalid rows, invalid UUIDs, and missing required tables.

### Safe replace imports

- [ ] Prevent replace mode from treating missing user-data tables as empty tables.
- [ ] Reject incomplete replace imports before deleting any local data.
- [ ] Decide and document whether replace means:
  - [ ] Replace all user data while preserving the exercise catalogue; or
  - [ ] Restore the complete database, including catalogue data, through an explicit separate operation.
- [ ] Ensure a normal full export cannot delete or overwrite the local exercise catalogue during user-data replacement.
- [ ] Add a regression test with a local custom exercise and a full export.
- [ ] Add a regression test proving a truncated backup cannot delete workouts, programs, templates, timer sessions, or body metrics.

### Database schema compatibility

- [ ] Compare imported `dbSchemaVersion` with the current database schema version.
- [ ] Reject exports from a newer unsupported database schema.
- [ ] Add explicit migration functions for supported older export schemas.
- [ ] Reject unsupported or ambiguous schema versions with a clear user-facing message.
- [ ] Add tests for older, current, newer, and unsupported `dbSchemaVersion` values.

### Transactional imports and snapshots

- [ ] Make the pre-import snapshot a consistent database snapshot/read transaction.
- [ ] Ensure snapshot creation completes successfully before any destructive import work begins.
- [ ] Make XLSX import atomic across:
  - [ ] Custom exercise creation.
  - [ ] Workout creation.
  - [ ] Workout-exercise creation.
  - [ ] Set creation.
- [ ] Roll back all XLSX changes if any workout or row fails.
- [ ] Make CSV program import atomic across all programs, or provide explicit and tested partial-import semantics.
- [ ] Add failure-injection tests proving no partial import remains after an error.

### Unknown exercise handling

- [ ] Decide whether unknown XLSX exercises are skipped or created as custom exercises.
- [ ] Align the implementation, README, preview UI, and tests with that decision.
- [ ] If custom exercises are created:
  - [ ] Mark them explicitly as user-created/custom.
  - [ ] Define their muscle, equipment, instruction, and media defaults.
  - [ ] Include their creation in the import preview.
  - [ ] Define whether they are included in export/import.
  - [ ] Ensure delete-all-user-data handles them according to their ownership.
- [ ] Never silently guess an unknown exercise mapping.

## Priority 1 — Reliability and correctness

### Duplicate historical imports

- [ ] Detect repeated XLSX imports using a stable source identity or file hash.
- [ ] Detect likely duplicate workouts using date, source sheet/day, exercise structure, and set data.
- [ ] Show duplicate candidates in the preview before writing.
- [ ] Make retrying an interrupted import safe and predictable.
- [ ] Add tests for importing the same workbook twice and for retrying after a simulated failure.

### Body-metric date normalization

- [ ] Normalize body-metric dates consistently to UTC midnight.
- [ ] Update `getByDate` to use UTC normalization.
- [ ] Update `deleteByDate` to use UTC normalization.
- [ ] Normalize range-query boundaries consistently.
- [ ] Add tests using local and UTC `DateTime` values, including non-UTC offsets where possible.

### Active workout draft persistence

- [ ] Serialize draft persistence writes so older asynchronous writes cannot overwrite newer state.
- [ ] Alternatively, add a monotonically increasing draft revision and ignore stale writes.
- [ ] Verify all set-row input updates use the intended 300 ms debounce.
- [ ] Verify draft restoration after process termination/app restart.
- [ ] Add a regression test for rapid sequential mutations and persistence ordering.
- [ ] Add a widget/integration test for deleting a middle set while editing values in neighboring rows.

### Database indexes

- [ ] Add explicit indexes required by ADR-1 and common query paths:
  - [ ] `workouts_table.started_at`
  - [ ] `workout_exercises_table.workout_id`
  - [ ] `workout_exercises_table.exercise_id`
  - [ ] `workout_sets_table.workout_exercise_id`
  - [ ] `workout_sets_table.set_index`
  - [ ] Program/template relationship columns.
  - [ ] Timer interval relationship columns.
- [ ] Add the indexes through explicit Drift migration steps.
- [ ] Confirm indexes exist in the generated SQLite schema.
- [ ] Benchmark history and analytics queries with a representative large dataset.

## Priority 2 — Quality gates and release readiness

### Formatting and CI

- [ ] Format the 19 files currently reported by:

  ```bash
  dart format --output=none --set-exit-if-changed .
  ```

- [ ] Re-run the formatting check and confirm it passes.
- [ ] Confirm CI runs formatting after code generation in a deterministic order.
- [ ] Consider adding `--delete-conflicting-outputs` to the CI build-runner command if generated-file conflicts are possible.

### Analyzer and platform builds

- [ ] Re-run:

  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  ```

  in an environment where Flutter can write its iOS ephemeral directory.

- [ ] Run the complete test suite with coverage.
- [ ] Build Android debug/release artifacts.
- [ ] Build Web release.
- [ ] Verify iOS build and CocoaPods integration on macOS.
- [ ] Resolve or document the Web font warning involving `CupertinoIcons`.
- [ ] Test whether all icon families used by the app render correctly in the browser.

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
- [ ] Verify all icon-only buttons have meaningful semantic labels/tooltips.
- [ ] Verify minimum interactive targets are at least 48 dp.
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

- [ ] Add export/import tests for full-catalogue replace behavior.
- [ ] Add export/import tests for incomplete and truncated envelopes.
- [ ] Add schema compatibility and export migration tests.
- [ ] Add referential-integrity validation tests.
- [ ] Add snapshot consistency/rollback tests.
- [ ] Add atomic CSV program-import failure tests.
- [ ] Add atomic XLSX import failure tests.
- [ ] Add unknown-exercise behavior tests based on the final product decision.
- [ ] Add duplicate XLSX import tests.
- [ ] Add body-metric timezone/date-boundary tests.
- [ ] Add draft persistence race/order tests.
- [ ] Add database index/schema migration tests.
- [ ] Add app-restart integration coverage for active workouts.
- [ ] Add timer background/foreground integration coverage where the platform test environment permits it.

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
