# FitTrack

Offline-first workout tracker. Flutter — Android, iOS, Web.

## Status

M0–M2 validate locally (`flutter analyze` and the full test suite are green).
M3 (Tracker) is source-complete and covered by unit/widget tests. M4 (Timer)
core is complete — wall-clock engine, presets, controller, capability services
(haptics/audio/notifications/wakelock) and UI — with a few platform-specific
follow-ups noted below. M5 (Progress & analytics) is source-complete with charts
for body weight, 1RM, volume, and muscle-group distribution. M6 (Dashboard,
settings, export/import) is complete — reactive dashboard cards, settings with
theme/units/feedback, versioned JSON/CSV export, validated import with merge/
replace and pre-import snapshot, and typed delete-all confirmation. M7 is in progress: automated hardening is covered by tracker/timer/DAO suites,
and the project currently passes analysis and all tests. iOS and Web scaffolding
is now present. Device profiling, release packaging, accessibility audits,
localization, and store-readiness work remain platform/release tasks. The
optional Riverpod custom-lint stack is currently blocked by an analyzer-version
conflict between the pinned build tooling and the latest compatible custom-lint
packages; the standard Flutter analyzer remains clean.

| Milestone | Scope | State |
|---|---|---|
| M0 | Repo, tooling, CI, ADRs | done |
| M1 | Theme, router shell, shared widgets | done |
| M2 | Drift schema + Library module | done |
| M3 | Tracker module | source-complete; validate on device |
| M4 | Timer module | core complete; see follow-ups |
| M5 | Progress & analytics | source-complete |
| M6 | Reactive dashboard, settings, export/import | done |
| M7 | Hardening, a11y, release | in progress; automated checks green |

## Setup

This repository includes generated Android, iOS, and Web scaffolding for
on-device/browser testing. See `SETUP.md` for the one-time steps to configure
platform-specific signing and capabilities.

Once set up:

    flutter pub get
    dart run build_runner build
    flutter run

`build_runner` is required before the first compile: `*.g.dart` files are
gitignored, so `themeModeControllerProvider` will not exist until you
generate it.

## Architecture

`docs/ADR.md` is binding. Read it before writing code, and paste it into the
context of any AI-assisted session.

Summary: Drift (SQLite) for persistence · Riverpod codegen for state ·
go_router with a 5-branch `StatefulShellRoute` · wall-clock timer engine ·
UUID-keyed nested form state · web-safe capability services · versioned
export envelope.

`docs/build-plan.md` holds the full milestone plan, exit criteria and risk
register. `docs/M0-SETUP.md` is the tooling runbook.

## Programs & spreadsheet import

The **Tracker** tab now lists training programs (Full Body, Upper/Lower,
Push/Pull/Legs) above workout history. Open a program to see its day-templates
(Workout A/B/C…) and start one as a workout.

Programs can be imported from a **CSV** spreadsheet (Excel can save/export
`.csv`). Use the import button next to the Programs heading. Expected header:

    program,day,exercise,sets,reps

- `program` — the program name (groups rows into a program).
- `day` — the day label, e.g. `Workout A`.
- `exercise` — matched against the seeded exercise catalogue by name.
- `sets` — target sets (integer).
- `reps` — optional, e.g. `8-12` (empty means AMRAP).

Unknown exercise names are skipped and reported before import.

### Historical XLSX workout import

The Tracker history header includes an XLSX import action for the structured
workout tracker format used by the supplied `Intermediate (V1-3 day)` workbook.
It reads dated workout columns across all sheets, maps exercise names to the
seeded catalogue, imports completed reps and weights into workout history, and
shows a preview before writing. Select the workbook's source unit during the
preview; values are always converted to kilograms in storage. Imported workouts
then appear in the calendar, history, estimated-1RM, volume, frequency, and
muscle-group analytics automatically. Unknown exercise names are reported and
added to the local catalogue as custom exercises rather than guessed.

## Commands

    dart run build_runner watch
    dart format .
    flutter analyze --fatal-infos --fatal-warnings
    flutter test --coverage

## Conventions

- Weight is stored in kilograms. Conversion happens in
  `core/formatters/unit_formatters.dart` and nowhere else.
- No magic numbers. Spacing, radii and durations come from
  `core/theme/app_spacing.dart`.
- Numbers that change live use tabular figures
  (`core/theme/app_typography.dart`).
- `presentation/` may import `domain/`. `domain/` imports neither `data/`
  nor `presentation/`.
