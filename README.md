# Ironyx

Offline-first workout tracker. Flutter — Android first; iOS and Web build but
are not launch targets (see `TODO.md` decisions D1 and D5). English and
Arabic (RTL).

## Status

**Not published yet.** The v1 feature set is built and the project is in its
pre-launch phase: a 12-week launch plan (Sep 28 – Dec 20, 2026) tracked in
`TODO.md`, targeting an Android store go-live on Tue Nov 17.

Checked 2026-09-20: `flutter analyze --fatal-infos --fatal-warnings` is
clean and `flutter test` reports **423 passed, 1 skipped, 0 failed**. All
device testing so far has been on an Android 15 emulator; nothing has been
run on a physical device, and nothing has been run on iOS at all.

| Milestone | Scope | State |
|---|---|---|
| M0 | Repo, tooling, CI, ADRs | done |
| M1 | Theme, router shell, shared widgets | done (teal brand — decision D3) |
| M2 | Drift schema + Library (301 exercises, public-domain media) | done |
| M3 | Tracker: workouts, history, calendar, programs, XLSX/CSV import | done in code; real-device validation open |
| M4 | Timer: wall-clock engine, presets, notifications, haptics | core done; sound cues use the OS alert (no cue files bundled); device validation open |
| M5 | Progress & analytics: insights, consistency, strength, RPE/rest | done |
| M6 | Dashboard, settings, versioned export/import, delete-all | done |
| M7 | Hardening, a11y, release | superseded by the launch plan in `TODO.md` |
| Accounts | Optional Supabase sign-in, password recovery, in-app account deletion, manual cloud backup (ADR-8) | built; not yet tested against a real project end to end |

What is still open before launch, in short: a physical-device validation
pass, the release signing key (not on the current dev machine), store
listing assets, hosting the privacy policy, the telemetry decision (D2), the
Play closed-test gate, and real audio cues. `TODO.md` has the dated,
owner-tagged list — read its "Launch plan" section first.

## Setup

See `SETUP.md` for prerequisites, Supabase and release-signing set-up, and
Windows notes. Short version:

    flutter pub get
    dart run build_runner build
    flutter run --dart-define-from-file=supabase.json

`build_runner` is required before the first compile: `*.g.dart` and
`*.freezed.dart` are gitignored, so generated providers do not exist until
you generate them.

### Accounts (Supabase) credentials

Sign-in is optional — workouts are stored on-device either way — but the
credentials are `String.fromEnvironment` constants, so they are baked in at
**compile time**. A build that omits them ships with auth disabled and Settings
shows "Accounts unavailable"; hot reload cannot fix it, only a rebuild can.

Copy `supabase.example.json` to `supabase.json` (gitignored) and fill in your
project URL and anon/publishable key, then use any of:

    scripts/build_android.sh run       # debug on the connected device
    scripts/build_android.sh apk       # release APK
    scripts/build_android.sh bundle    # release AAB for Play
    scripts/build_android.sh install   # release APK, installed on the device

VS Code users can pick the **Ironyx (debug)** launch configuration instead;
`.vscode/launch.json` passes the same flag. Never hand out a bare
`flutter build apk` — it silently has accounts off.

## Architecture

`docs/ADR.md` is binding. Read it before writing code, and paste it into the
context of any AI-assisted session. Several ADRs carry dated amendments
recording where the code has moved or deviates; read those too.

Summary: Drift (SQLite) for persistence · Riverpod codegen for state ·
go_router with a 5-branch `StatefulShellRoute` · wall-clock timer engine ·
UUID-keyed nested form state · web-safe capability services · versioned
export envelope · optional Supabase accounts behind an `AuthService` seam.

Documentation map:

| File | What it is |
|---|---|
| `TODO.md` | The live tracker: 12-week launch plan, decisions, audits, checklists |
| `PLAN.md` | Release, platforms and revenue phases, each with a gate |
| `docs/ADR.md` | Binding architecture decisions and amendments |
| `docs/widgets.md` | Shared widget reference |
| `docs/PRIVACY_POLICY.md` | The privacy policy (not yet publicly hosted) |
| `docs/STORE_LISTING.md` | Play Store listing drafts and ASO notes |
| `docs/cloud_backup_setup.sql` | One-time Supabase server set-up (backup table, RLS, account deletion) |
| `docs/v2-ideas.md` | Parked ideas — nothing here is in v1 |
| `docs/build-plan.md`, `docs/M0-SETUP.md` | Historical: the original build plan and M0 runbook |
| `ASSETS-LICENSE.md` | Licence of every shipped asset, enforced in CI |
| `SETUP.md` | Getting a working checkout, signing and releasing |

## Programs & spreadsheet import

The **Tracker** tab lists training programs (Full Body, Upper/Lower,
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
added to the local catalogue as custom exercises rather than guessed. Re-importing
the same workbook is detected by content and skipped, and an import is atomic —
a failure leaves nothing behind.

## Commands

    dart run build_runner watch
    dart format .
    flutter analyze --fatal-infos --fatal-warnings
    flutter test --coverage
    dart run tool/check_asset_licenses.dart   # false-fails on Windows; see SETUP.md

`riverpod_lint` / `custom_lint` are not enabled (analyzer-version conflict
with the pinned build tooling); the standard analyzer plus the strict options
in `analysis_options.yaml` is what runs, in CI as well.

## Conventions

- Weight is stored in kilograms. Conversion happens in
  `core/formatters/unit_formatters.dart` and nowhere else.
- No magic numbers. Spacing, radii and durations come from
  `core/theme/app_spacing.dart`.
- Numbers that change live use tabular figures
  (`core/theme/app_typography.dart`).
- Every user-facing string lives in `lib/l10n/*.arb`, in English **and**
  Arabic; an untranslated key is reported in `lib/l10n/untranslated.json`.
- `presentation/` may import `domain/`. `domain/` imports neither `data/`
  nor `presentation/`.
