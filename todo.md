# FitTrack Engineering TODO

> Last updated: 2026-08-22  
> Source: code review notes (see commit history for full analysis)

---

## P0 — Correctness bugs in shipped functionality

### 1. [DONE] Body-weight delete is a no-op (LIVE BUG)
**Files:** `progress_page.dart:1065`, `body_metrics_dao.dart:25,45`, `body_metrics.dart:39`  
**Problem:** Write path stores full local timestamp (`DateTime.now()`); DAO delete/get truncate to local midnight (`DateTime(y,m,d)`). Epoch-int equality never matches → delete does nothing. `UNIQUE (date)` invariant is unenforced (can log 10 entries/day).  
**Fix:** Normalize to UTC midnight on **write** (or read), add `BodyMetricsDao` unit tests.

### 2. [DONE] XLSX import not atomic
**File:** `workout_xlsx_import_service.dart:91-175`  
**Problem:** Bare `await` loop, no `db.transaction`. Custom-exercise insert colliding with `exercises_table.name` UNIQUE throws mid-loop → guaranteed partial import.

### 3. [DONE] CSV program import not atomic
**File:** `program_import_service.dart:114` (`apply()`)  
**Problem:** Same — no transaction wrapper.

### 4. [DONE] Snapshot export isn.t a consistent read
**File:** `data_export_service.dart` (`buildJsonExport`)  
**Problem:** Loops `db.allTables` with separate `customSelect` each, no read transaction.

### 5. [DONE] Envelope field validation missing
**File:** `export_envelope.dart:99-102`  
**Problem:** `dbSchemaVersion as int? ?? 0`, `exportedAt` falls back to epoch, `appVersion` to `'unknown'`. No validation on import.

### 6. [DONE] No `dbSchemaVersion` check on import
**File:** `applyImport`  
**Problem:** Never reads envelope `dbSchemaVersion`. Current `schemaVersion` is 5 with real `onUpgrade` — old exports genuinely can't apply.

### 7. [DONE] Column-name injection surface
**File:** `data_export_service.dart:164-173`  
**Problem:** `rows.first.keys` interpolated straight into SQL string. Table names are safe (iterates `db.allTables`), but columns are not.

### 8. [DONE] Variable column sets per row silently corrupt import
**File:** `applyImport`  
**Problem:** Derives columns from `rows.first.keys` only — rows with differing key sets get NULLs or dropped columns.

---

## P1 — Safety / data-integrity gaps

### 9. [DONE] Zero database indexes
**Evidence:** `grep TableIndex\|CREATE INDEX` across `lib/` → 0 hits.  
**ADR promise:** `docs/ADR.md:17` — *"Every table gets its indexes in the initial migration"*  
**Action:** Add indexes per ADR.

### 10. [DONE] Full export can silently downgrade exercise catalogue
**Files:** `data_export_service.dart:26-38,145` (`_catalogueTableNames`, `skipInReplace`), doc comment line 120  
**Problem:** Guards only when catalogue keys are **absent**. On normal full export, keys are present → replace does `DELETE FROM exercises_table` + reinsert from backup. Doc comment claims *"The exercise catalogue is left alone entirely"* — false for common case. Restoring year-old backup silently downgrades catalogue.  
**Fix:** Make catalogue preservation unconditional; correct doc comment.

### 11. [DONE] Pre-import snapshot written to disk, never surfaced, never cleaned up, no restore path
**File:** `data_export_service.dart` (snapshot logic)  
**Problem:** Unbounded disk growth; safety net user can't reach.

### 12. [DONE] Unknown-exercise doc mismatch
**Files:** `README.md:80,91` vs `workout_xlsx_import_service.dart:100-113`  
**Problem:** README says unknown names are *"skipped and reported"*; code **creates them** as catalogue rows with `seedVersion: 0`.

---

## P2 — Developer experience / CI unblockers

### 13. CI red at first step since redesign commit
**File:** `.github/workflows/ci.yaml`  
**Problem:** Formatting is step 3; analyze, test, build-apk, build-web have not executed since. "Format 19 files" is the unblocker for all of Priority 2.  
**Action:** Run `dart format .` (one command), push — unblocks entire pipeline.

### 14. [DONE] Set-row input writes entire draft to SharedPreferences on every keystroke (no debounce)
**Files:** `draft_editor_widgets.dart:450,468` → `updateSet` → `_updateExercise` → `_persist()`  
**Problem:** `AppDuration.inputDebounce` (300 ms, `app_spacing.dart:34`) used only in two search fields (`library_page.dart:82`, `exercise_picker_sheet.dart:52`). Set rows bypass it entirely.  
**Action:** Add debounce to set-row inputs; this also fixes the race condition noted in the original list.

### 15. "Confirm CI runs formatting after code generation" / "--delete-conflicting-outputs" — false premises
**Evidence:** `.gitignore:59-60` excludes `*.g.dart` and `*.freezed.dart`; `git ls-files` confirms zero generated files tracked.  
**Correction:** Format-before-codegen is correct order; moving after would format-check generated code. `--delete-conflicting-outputs` is a no-op on clean checkout.  
**Action:** Remove these items from backlog.

---

## P3 — Polish / consistency

### 16. [DONE] Preview doesn.t flag partial/truncated import files
**File:** `data_management_section.dart:180-185`  
**Problem:** Shows counts for 5 hardcoded tables only; truncated file just shows fewer lines.

### 17. [DONE] Reject unknown table names (user feedback, not safety)
**Context:** Apply loop iterates `db.allTables` — unknown table names silently ignored, never interpolated into SQL. Worth doing for UX, but not a safety hole.

---

## P4 — Removed / duplicates

The original list had ~10 duplicate entries across P0/P1/P4 (lines 54≈181, 76≈183, 84≈184, 41≈177). Those have been collapsed above.

---

## Suggested landing order

1. [DONE] **Format 19 files** → unblocks CI (~1 command)
2. [DONE] **Body-metric date bug + DAO tests** (P0 #1)
3. [DONE] **Wrap XLSX/CSV imports in transactions** (P0 #2, #3)
4. [DONE] **Envelope validation + schema-version gate*** (P0 #5, #6)
5. [DONE] **Column-name injection fix** (P0 #7)
6. [DONE] **Variable column set handling** (P0 #8)
7. [DONE] **Consistent-read export snapshot** (P0 #4)
8. [DONE] **Indexes per ADR*** (P1 #9)
9. [DONE] **Catalogue preservation fix + doc correction*** (P1 #10)
10. [DONE] **Snapshot cleanup / restore path*** (P1 #11)
11. [DONE] **Unknown-exercise doc/code alignment** (P1 #12)
12. [DONE] **Set-row input debounce*** (P2 #14)
13. [DONE] **Preview partial-file detection** (P3 #16)
14. [DONE] **Unknown-table rejection (UX)** (P3 #17)

---

## Non-code pre-release QA (separate track)

- Device testing: import/export round-trips (XLSX, CSV, JSON)
- Device testing: body-weight CRUD across DST boundaries
- Device testing: catalogue downgrade/upgrade scenarios
- Performance: large workout history (>5k sets) import/export
- Accessibility audit