# Flutter Fitness App — Professional Build Plan

**Version:** 1.0
**Target platforms:** Android, iOS, Web (responsive)
**Model:** Offline-first, single-user, no backend in v1
**Estimated effort:** 6–8 weeks solo (AI-assisted), ~120–160 focused hours

---

## 0. How to use this document

The prompt sequence you have is a good *feature* outline but it is not yet a *build* plan. It has no quality gates, no test strategy, no release path, and a few architectural choices that will hurt you in Phase 3. This document fixes that.

Work top to bottom. Do not start a milestone until the previous milestone's **Exit criteria** are all green. Each milestone ends with a commit tag so you can roll back.

---

## 1. Scope definition

### In scope (v1)

| Module | Core capability |
|---|---|
| Dashboard | Live summary cards, entry point to all modules |
| Tracker | Log workouts: exercises → sets → reps/weight, save to history |
| Library | 50+ seeded exercises, search, filter by muscle/equipment |
| Timer | Interval timer (presets + custom builder), haptics, background-safe |
| Progress | Estimated 1RM trend, weekly volume, body metrics |
| Settings | Theme toggle, units (kg/lb), data export/import |

### Explicitly out of scope (v1)

Cloud sync, user accounts, social features, video demonstrations, wearable integration, nutrition tracking, AI coaching. Write these on a `v2-ideas.md` file and stop thinking about them.

### Non-functional requirements

- Cold start to interactive dashboard: **< 2s** on a mid-range Android device
- All list scrolling: **60 fps**, no jank on 500+ history entries
- Zero data loss: every write is durable before the UI confirms success
- Works fully offline, always
- Accessible: minimum tap target 48dp, screen-reader labels on all icon-only buttons

---

## 2. Architecture decisions (and 6 corrections to your original plan)

These are the decisions that are expensive to change later. Make them now, at the start, while the cost is zero.

### ADR-1 — Persistence: use Drift (SQLite), not Hive ⚠️ **change**

Your prompt specifies `hive_flutter`. Two problems:

1. **Maintenance.** Hive's original package has been effectively dormant; the actively maintained path is the community fork `hive_ce`. Verify current status before you commit either way.
2. **The real issue — query shape.** Phase 3 asks for "total volume per week" and "1RM over time for the most frequent lifts." Those are `GROUP BY`, `JOIN`, and `ORDER BY` queries. Hive is a key-value store. You would load every workout into memory and aggregate by hand in Dart — which works at 50 workouts and falls over at 2,000.

**Decision:** `drift` (SQLite) as the single source of truth for exercises, workouts, sets, timer sessions, and body metrics. `shared_preferences` for trivial settings (theme mode, unit preference). Drift supports Android, iOS, and Web (WASM), gives you type-safe SQL, reactive `Stream` queries that feed Riverpod directly, and real schema migrations.

**If you insist on staying close to the original prompt:** use `hive_ce`, and accept that you will hand-write all aggregation logic and have no migration tooling.

### ADR-2 — State management: Riverpod with code generation ⚠️ **change**

Your prompt says `StateNotifier`. That is the legacy API. Use `@riverpod` annotations with `riverpod_generator`, and `Notifier` / `AsyncNotifier` classes. Benefits: compile-time safety on provider arguments, no manual `provider` declarations to keep in sync, automatic `autoDispose`, and far better refactoring.

Add `riverpod_lint` + `custom_lint` on day one. It catches the entire class of "provider read inside build" bugs for free.

### ADR-3 — Navigation: 5 tabs, not 4 ⚠️ **gap in original plan**

Your Prompt 2 defines a 4-tab bottom bar (Tracker, Library, Timer, Progress) *and* a Dashboard home page — but never says how the Dashboard is reached. Resolve it now:

**Decision:** 5 branches in `StatefulShellRoute.indexedStack`: **Home · Tracker · Library · Timer · Progress**. Home is index 0 and the app's start destination. Five is the maximum for a Material bottom nav bar; do not add a sixth. Settings lives behind an icon in the Home app bar, not in the nav bar.

**Detail-route placement — decide now, not at M5.** Two options, and mixing them arbitrarily is what produces "why did the back button do that" bugs:

- **Root-level routes pushed over the shell** (`parentNavigatorKey: rootNavigatorKey`): full-screen, bottom bar hidden, single linear back stack.
- **Inside the branch navigator:** bottom bar stays visible, each tab keeps its own back stack.

**Rule for this app:** anything that is a *focused task* goes root-level over the shell — active workout session, workout history detail, exercise detail full page, timer running screen, settings. Anything that is *browsing within a tab's subject matter* stays inside the branch. In v1 that leaves essentially nothing in the second category, which is fine and is the simpler outcome.

The active workout session is the clearest case: the bottom bar must not be visible mid-set, because a mistaken tap on "Library" during a working set is infuriating. Hiding chrome also signals "you are in a mode you should deliberately exit."

One consequence to accept: root-level routes mean the Library tab does not remember that you were three levels deep when you switch away. For a fitness app that is correct behaviour, not a regression.

### ADR-4 — Timer must be wall-clock based ⚠️ **gap in original plan**

A timer built on a `Ticker` that accumulates elapsed frames will drift, and will silently stop when the app is backgrounded or the screen locks — during exactly the 30 seconds the user is doing burpees. This is the single most common way fitness timers get 1-star reviews.

**Decision:** Store `startedAt` as a timestamp and compute remaining time as `endsAt - DateTime.now()` on every tick. On backgrounding, schedule a `flutter_local_notifications` alert for the interval boundary. Use `wakelock_plus` to keep the screen on during an active session. On resume, recompute from wall clock — never from accumulated state.

### ADR-5 — Nested form state: controllers are owned by rows, not by lists ⚠️ **risk in original plan**

Your Prompt 4 proposes "`TextEditingController` lists" for nested sets. Managed centrally this leaks controllers and breaks when a user deletes a middle set (indices shift, text jumps to the wrong row).

**Decision:** The workout draft (exercises, sets, reps, weight) lives in a Riverpod `Notifier` as **immutable data**, keyed by a stable generated `setId` — never by list index. Each set row is a small `StatefulWidget` that owns and disposes its own controllers, initialised from the model and pushing changes up on `onChanged` (debounced 300ms). Use `freezed` for the draft models so `copyWith` on deeply nested state stays readable.

### ADR-6 — Web is a first-class target, so degrade gracefully

`HapticFeedback` is a no-op on web. Local notifications behave differently. Hover and mouse-wheel scrolling need explicit handling. Wrap every platform-specific capability behind a small service interface with a web implementation, so a missing capability is a no-op rather than an exception.

### Final dependency set

```yaml
dependencies:
  flutter_riverpod: ^2.5.0        # verify latest at install time
  riverpod_annotation: ^2.3.0
  go_router: ^14.0.0
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  fl_chart: ^0.68.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0
  shared_preferences: ^2.2.0
  flutter_local_notifications: ^17.0.0
  wakelock_plus: ^1.2.0
  just_audio: ^0.9.0              # in-app cues; see note below
  intl: ^0.19.0

dev_dependencies:
  build_runner: ^2.4.0
  riverpod_generator: ^2.4.0
  riverpod_lint: ^2.3.0
  custom_lint: ^0.6.0
  drift_dev: ^2.18.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  flutter_lints: ^4.0.0
  mocktail: ^1.0.0
  golden_toolkit: ^0.15.0
```

**On audio:** `flutter_local_notifications` covers *background* alerts only. In-app beeps and the 3-2-1 countdown need a real audio package, or you end up abusing `SystemSound.play` — which gives you a click on Android and nothing useful on iOS. Preload the cue files as `AudioSource` objects at session start; do not construct a player per beep, or the first cue of every round arrives late. `just_audio` has slightly higher cold-start latency than `audioplayers` for very short clips — if you measure a perceptible lag on a real device with preloading in place, swap to `audioplayers` and move on. Also configure the iOS audio session category so cues duck the user's music rather than stopping it.

Pin exact versions in `pubspec.lock` and commit it. Check each package's current version and null-safety/platform support before installing — the numbers above are a starting point, not gospel.

---

## 3. Project structure

Feature-first, layered inside each feature. This keeps AI-assisted edits contained to one directory.

```
lib/
├── main.dart
├── app.dart                       # MaterialApp.router + theme wiring
├── core/
│   ├── theme/                     # ColorScheme, TextTheme, ThemeMode notifier
│   ├── router/                    # go_router config, route names, shell
│   ├── database/                  # Drift database, tables, DAOs, migrations
│   ├── services/                  # haptics, notifications, wakelock (+ web stubs)
│   ├── formatters/                # weight/date/duration formatting, unit conversion
│   └── widgets/                   # shared: AppCard, EmptyState, ErrorView, LoadingView
├── features/
│   ├── dashboard/  { data/ domain/ presentation/ }
│   ├── tracker/    { data/ domain/ presentation/ }
│   ├── library/    { data/ domain/ presentation/ }
│   ├── timer/      { data/ domain/ presentation/ }
│   ├── progress/   { data/ domain/ presentation/ }
│   └── settings/   { data/ domain/ presentation/ }
└── assets/
    └── data/exercises_seed.json
test/
├── unit/          # repositories, DAOs, 1RM & volume calculators
├── widget/        # per-screen widget tests
└── golden/        # visual regression, light + dark
integration_test/  # full user journeys
```

**Rule:** `presentation/` may import `domain/`. `domain/` may import nothing from `presentation/` or `data/`. `data/` implements interfaces defined in `domain/`. Enforce it in review; violations are how a codebase rots.

---

## 4. Data model

```
exercises          id, name, primary_muscle, secondary_muscles(json),
                   equipment, movement_type, instructions, is_custom, created_at

workouts           id, name, started_at, ended_at, notes

workout_exercises  id, workout_id → workouts, exercise_id → exercises, order_index

workout_sets       id, workout_exercise_id → workout_exercises, set_index,
                   reps, weight_kg, is_warmup, is_completed, rpe (nullable)

templates          id, name, created_at, payload(json snapshot)

timer_sessions     id, preset_name, total_duration_s, rounds, completed_at

body_metrics       id, recorded_at, weight_kg, body_fat_pct (nullable)
```

**Indexes:** `workouts(started_at)`, `workout_exercises(workout_id)`, `workout_sets(workout_exercise_id)`, `exercises(primary_muscle)`. Add them in the initial migration, not later.

**Store weight in kilograms, always.** Convert to pounds only at the display layer. Mixing units in the database is a bug you will be chasing for months.

### Enums

- `MuscleGroup`: chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, core, fullBody
- `Equipment`: barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other
- `MovementType`: compound, isolation

### Calculation formulas

**Estimated 1RM (Epley):** `1RM = weight × (1 + reps / 30)`

Only compute for sets with `reps` between 1 and 12 — Epley diverges badly at high rep counts. For `reps == 1`, return the weight itself. Label it "Est. 1RM" in the UI, never "1RM". Consider offering Brzycki (`weight × 36 / (37 − reps)`) as a settings toggle.

**Session volume:** `Σ (weight_kg × reps)` over completed, non-warmup sets.

Put both in `core/` as pure functions with unit tests. They are the only genuinely testable business logic in the app — get them right.

---

## 5. Milestone plan

### M0 — Repo & tooling (0.5 day)

- [ ] `flutter create` with correct org id and platforms (android, ios, web)
- [ ] Git repo, `.gitignore` verified, `main` + `develop` branches
- [ ] `analysis_options.yaml`: `flutter_lints` + `custom_lint` + `riverpod_lint`, warnings as errors in CI
- [ ] Add all dependencies; run `build_runner` once to confirm the toolchain works
- [ ] GitHub Actions: `flutter analyze` → `flutter test` → `flutter build apk --debug` on every push
- [ ] `README.md` with setup steps and the ADR summary from Section 2
- [ ] Folder skeleton from Section 3, each directory with a `.gitkeep`

**Exit:** CI is green on an empty project. Tag `v0.0.1-scaffold`.

---

### M1 — Design system & app shell (2 days)

- [ ] `ColorScheme.fromSeed` with electric-blue seed; hand-tune the charcoal surface tones for dark mode
- [ ] Typography scale — pick 2 families max (one display/monospace for numbers, one body). Number-heavy UI needs **tabular figures** so digits don't shift while counting
- [ ] Spacing constants (4/8/12/16/24/32) and radius constants in one file — no magic numbers anywhere else
- [ ] `ThemeModeNotifier` persisted to `shared_preferences`, with a system-default option
- [ ] `go_router` config: `StatefulShellRoute.indexedStack` with 5 branches (ADR-3)
- [ ] Bottom nav bar with correct Material 3 behaviour; state preserved per tab
- [ ] Deep-link-safe route names as constants — no string literals at call sites
- [ ] Shared widgets: `AppCard`, `EmptyState`, `ErrorView`, `LoadingShimmer`
- [ ] Dashboard with 5 static placeholder cards in a responsive grid (1 col mobile / 2 col tablet / 3 col web)
- [ ] Responsive breakpoint helper; verify at 360dp, 768dp, 1440dp

**Exit:** All 5 tabs navigate, state persists across tab switches, dark/light toggle works and survives restart. Root-level detail routing verified with one throwaway placeholder page (bottom bar hidden, back returns to the correct tab). Golden tests captured for the shell in both themes. Tag `v0.1.0-shell`.

---

### M2 — Database & Library module (3 days)

- [ ] Drift database class, all 7 tables, `schemaVersion: 1`, indexes
- [ ] Web support: WASM/IndexedDB path configured and tested in Chrome
- [ ] Curate `exercises_seed.json` — 50 exercises with real instructions, correct muscle mapping. **Budget 3–4 hours for this; it is content work, not coding.** Do not let an AI hallucinate exercise form cues, then ship them without review — bad instructions cause injuries
- [ ] Idempotent seeding on first launch, guarded by a `seed_version` flag
- [ ] `ExerciseDao`: `watchAll()`, `searchByName()`, `filterBy(muscle, equipment)`, `getById()`
- [ ] `ExerciseRepository` interface in `domain/`, Drift implementation in `data/`
- [ ] Riverpod providers exposing repository streams
- [ ] Library UI: search bar (debounced 300ms), filter chips, exercise list
- [ ] Exercise detail bottom sheet with full metadata
- [ ] Empty state ("no results") and error state
- [ ] Unit tests: DAO queries against an in-memory database, all filter permutations

**Exit:** Search + filter return correct results on 50 seeded exercises. Cold-start seeding < 500ms. Tag `v0.2.0-library`.

---

### M3 — Tracker module (4 days)

This is the hardest milestone. It is also the one users touch most. Slow down here.

- [ ] `WorkoutDraft` freezed models: draft → exercises → sets, every entity with a stable UUID
- [x] ActiveWorkoutNotifier: add/remove exercise, reorder, add/remove/duplicate set, update reps & weight, mark complete
- [ ] Set-row widget owning its own controllers with correct disposal (ADR-5)
- [ ] Numeric keyboard with decimal support; input validation (weight ≥ 0, reps 0–100)
- [ ] "Add exercise" flow launching the Library picker and returning a selection
- [x] Rest timer between sets, launched inline from the tracker
- [ ] Save: single transaction writing workout + exercises + sets. **Verify the write succeeded before showing the success snackbar**
- [ ] Discard with undo snackbar (5s window before the draft is actually dropped)
- [ ] Draft auto-persistence — if the app is killed mid-workout, restore on next launch. Non-negotiable
- [ ] Workout history list with date grouping; tap to view a read-only summary
- [ ] Edit and delete a past workout, with confirmation on delete
- [ ] Widget tests: add 3 exercises × 4 sets, delete the middle set, confirm no value corruption

**Exit:** Log a 6-exercise workout, force-kill the app mid-session, reopen, and find the draft intact. Tag `v0.3.0-tracker`.

---

### M4 — Timer module (2.5 days)

- [ ] Wall-clock timer engine (ADR-4) with unit tests covering pause, resume, and a simulated 10-minute background gap
- [ ] Circular progress indicator, large tabular-figure countdown
- [ ] Quick Start presets: HIIT 30/10, Strength 60/30, Tabata 20/10×8
- [ ] Custom Builder: work duration, rest duration, rounds, optional warm-up and cool-down
- [ ] Save custom presets to the database
- [ ] Haptics: start, round transition, 3-2-1 countdown, completion — behind a service, no-op on web
- [ ] Audio cues with a mute toggle, files preloaded at session start, iOS audio session configured to duck not interrupt
- [ ] **Notification permission flow.** iOS requires explicit authorisation, and Android 13+ needs `POST_NOTIFICATIONS`. Request it in context — when the user first starts a timer, with a one-line explanation of why — not on app launch. Cold permission prompts get denied
- [ ] **Denial fallback.** If permission is refused, the timer must still work: keep the wakelock on, keep audio and haptics running, and show a one-time dismissible banner explaining that alerts won't fire if the app is fully backgrounded. Never let a denied permission produce a silent failure
- [ ] Re-check permission status on each session start — users revoke in system settings
- [ ] Local notification scheduled on background, cancelled on foreground return
- [ ] Wakelock during an active session, released on exit
- [ ] Write a `timer_sessions` row on completion
- [ ] Screen-rotation and app-lifecycle handling verified on a real device

**Exit:** Start a 12-minute Tabata, lock the phone, put it in a pocket, and get correct audio + haptic cues throughout. Tag `v0.4.0-timer`.

---

### M5 — Progress & analytics (3 days)

- [x] Aggregation queries in SQL (not Dart): weekly volume, est. 1RM series per exercise, workout frequency
- [ ] Unit tests for Epley and volume calculators, including boundary cases (0 reps, 1 rep, 15 reps, 0 weight, bodyweight exercises)
- [ ] Est. 1RM line chart with exercise selector, ranges 1M / 3M / 1Y / all
- [ ] Weekly volume bar chart with muscle-group breakdown
- [ ] Interactive tooltips on touch; verify on both touch and mouse
- [ ] Personal-record detection and a PR badge on the history entry
- [ ] Body Metrics: log weight and body-fat %, chart over time, edit and delete entries
- [ ] Empty states for every chart — a new user has zero data and must not see a broken axis
- [ ] Charts render correctly in both themes; verify contrast on the dark background

**Exit:** With 3 months of seeded fake data, every chart renders correctly and responds to touch in under 100ms. Tag `v0.5.0-progress`.

---

### M6 — Reactive dashboard & settings (2 days)

- [x] Convert all 5 dashboard cards to Riverpod stream providers reading live data
- [x] Tracker card: most recent workout — name, duration, total volume
- [x] Timer card: last session name and duration
- [x] Library card: total exercise count, most recently added
- [x] Progress card: est. 1RM for the most-logged lift, with trend arrow
- [x] Per-card loading skeletons and error states — **one failing card must never blank the whole dashboard**
- [x] Card polish: subtle elevation, gradient, iconography, ripple on tap
- [x] Settings screen: theme mode, units (kg/lb), sound and haptics toggles
- [x] **Data export to JSON and CSV**, and import with validation. This is a trust feature — offline apps that can't back up lose users permanently
- [x] **Versioned export envelope.** Every export carries `formatVersion` (integer, independent of the app version), `dbSchemaVersion`, `appVersion`, and `exportedAt`. On import: reject unknown or newer `formatVersion` with a clear message, migrate older versions explicitly, and never attempt a best-effort parse of an unversioned file. Write the migration path for v1 → v2 now while there is only one version to reason about
- [x] Import is transactional and previewed: show counts ("312 workouts, 1,847 sets") and require confirmation before writing. Offer merge vs. replace, and take an automatic pre-import snapshot
- [x] "Delete all data" with a typed confirmation

**Exit:** Dashboard reflects a new workout within one frame of saving it. Export → wipe → import produces byte-identical data. Tag `v0.6.0-dashboard`.

---

### M7 — Hardening, polish & release (4 days)

**Performance**
- [ ] Profile with DevTools on a *release* build on a real mid-range device
- [ ] Fix unnecessary rebuilds: `select()` on providers, `Consumer` scoped as narrowly as possible
- [ ] `const` constructors everywhere the linter allows
- [ ] `ListView.builder` with `itemExtent` where item height is fixed
- [ ] Test with 500 workouts and 5,000 sets — measure, don't guess
- [ ] Confirm database connections close cleanly on lifecycle termination

**Quality**
- [x] `flutter analyze` — zero issues, zero ignores without a written justification
- [ ] Test coverage ≥ 70% on `domain/` and `data/`
- [ ] Integration tests for 3 full journeys: log a workout, run a timer, view progress
  (the current integration test is a destination smoke test; full journeys remain)
- [ ] Golden tests **scoped to the shell, dashboard cards, and charts only**, light and dark. Everything else gets ordinary widget tests. Goldens on every screen rot fast: any padding tweak fails a dozen tests at once and the team learns to run `--update-goldens` reflexively, which destroys their value. Pin font loading and run goldens on one fixed CI platform, or host-vs-CI antialiasing differences will fail builds that are actually fine
- [ ] Every user-facing string extracted for l10n, even if English is the only locale in v1

**Accessibility**
- [x] Semantic labels on every icon-only button
  (tooltips and explicit semantics are present on the audited controls; an on-device TalkBack/VoiceOver pass remains)
- [ ] TalkBack / VoiceOver pass over each screen
- [ ] Contrast ratios ≥ 4.5:1 verified in both themes
- [ ] Layout survives 200% system font scale without overflow

**Web**
- [ ] Mouse-wheel scrolling, hover states, keyboard focus order
- [ ] Verify at 1440px and 1920px — no stretched full-width mobile layouts
- [ ] Web build size checked; deferred loading if it's oversized

**Current M7 status:** automated analysis is clean, icon-only controls have
accessible labels, the unit/widget suite includes tracker and timer hardening
coverage, and Android, iOS, and Web scaffolding are present. Web now builds
successfully after isolating the VM-only Drift test executor from the production
bundle; Android debug APK builds successfully as well. Device profiling,
large-dataset benchmarking, accessibility/font-scale audits, golden baselines,
localization, production signing, and store-release preparation remain to be
completed on their target platforms. The optional Riverpod custom-lint stack is
blocked by an analyzer compatibility conflict with the currently pinned
build_runner/Freezed toolchain and should be revisited during a dependency
upgrade.

**Release**
- [ ] App icons and splash screens for all platforms
- [ ] Android: signing config, `minSdk` set, ProGuard rules, release build tested
  (scaffolding generated, debug-signed release APK builds successfully; production signing and R8/ProGuard verification remain)
- [ ] iOS: bundle id, capabilities, `Info.plist` usage descriptions, TestFlight build
- [ ] Privacy policy (required by both stores even for a fully offline app)
- [ ] Store listing: screenshots, description, category, content rating
- [ ] Crash reporting wired up (Sentry or Crashlytics) before the first public build
- [ ] Beta with 5–10 real users for one week; fix what they hit
- [ ] Tag `v1.0.0`

---

## 6. Definition of Done

A task is done when **all** are true:

1. Code compiles with zero analyzer warnings
2. Unit tests exist for any non-trivial logic and pass
3. Loading, empty, and error states are handled — not just the happy path
4. It works in both light and dark themes
5. It works on Android, iOS, and Web, or degrades gracefully with a documented reason
6. No hardcoded strings, colours, or spacing values
7. Manually tested on a real device, not only the simulator

---

## 7. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Hive chosen anyway, then analytics needs relational queries | High | Decide now (ADR-1). Migration after M5 costs a full week |
| Timer drifts or dies in background | High | ADR-4 wall-clock design; test on a real locked device early |
| Nested tracker state corrupts on edit | High | Stable IDs not indices (ADR-5); widget tests in M3 |
| AI-generated exercise instructions are wrong | High | Human review of all 50 entries against a reputable source |
| Scope creep from the v2 list | Medium | `v2-ideas.md`; nothing enters v1 after M2 |
| fl_chart limitations on complex interactions | Medium | Prototype the 1RM chart during M2, not M5 |
| iOS notification permission denied, background alerts fail silently | High | In-context request + explicit fallback (M4) |
| Unversioned exports become unimportable after a schema change | Medium | `formatVersion` envelope from the first export ever written |
| Golden tests become brittle, team disables them | Medium | Narrow scope, pinned fonts, single CI platform |
| Web build too large / slow | Low | Measure at M6; deferred loading if needed |

---

## 8. Working with AI assistance

Your original document was a prompt sequence, so a note on using it well:

- **One milestone per session.** Long AI sessions drift from the architecture and start inventing patterns. Start a fresh session per milestone with the ADRs pasted in as context.
- **Paste the ADRs every time.** The assistant does not remember your decisions between sessions and will happily reintroduce `StateNotifier` and index-keyed controllers.
- **Never accept database or state-management code without reading it line by line.** These are the two places where a plausible-looking bug costs you a week.
- **Ask for tests in the same prompt as the implementation.** Retrofitted tests test what the code does, not what it should do.
- **Verify every package version and API** against current documentation. Training data ages; Flutter moves fast.

---

## 9. Suggested schedule

| Week | Milestones | Deliverable |
|---|---|---|
| 1 | M0 + M1 | Navigable themed shell |
| 2 | M2 | Working exercise library |
| 3 | M3 | Workout logging end to end |
| 4 | M4 | Timer complete |
| 5 | M5 | Analytics live |
| 6 | M6 | Feature-complete app |
| 7–8 | M7 | Hardened, beta-tested, submitted |

Add 30% buffer if this is part-time work. Every project of this size hits at least one two-day problem that nobody predicted.
