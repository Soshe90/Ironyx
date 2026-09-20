# Architecture Decision Record

**Status:** Accepted, M0. Binding for all v1 work.
**Purpose:** This file is the contract for the codebase. Paste it into the context of every AI-assisted coding session before asking for code. If a suggestion contradicts anything below, the suggestion is wrong.

---

## ADR-1 — Persistence: Drift (SQLite)

**Decision:** `drift` is the single source of truth for exercises, workouts, workout_exercises, workout_sets, templates, timer_sessions, and body_metrics. `shared_preferences` holds only trivial UI settings (theme mode, unit preference, sound/haptic toggles).

**Rejected:** Hive / hive_ce. The Progress module needs weekly volume aggregation and per-exercise 1RM series over time — `GROUP BY`, `JOIN`, `ORDER BY` queries. A key-value store forces hand-written Dart aggregation over the full dataset, which is fine at 50 workouts and unusable at 2,000. Drift also gives schema migrations, type-safe queries, and reactive `Stream`s that plug straight into Riverpod.

**Binding rules:**
- All aggregation happens in SQL, never by loading rows into Dart and folding them.
- Weight is stored in **kilograms**, always. Convert to pounds at the display layer only.
- Every table gets its indexes in the initial migration, not retrofitted.
- `schemaVersion` is incremented with an explicit migration step for every model change. No exceptions.

---

## ADR-2 — State: Riverpod with code generation

**Decision:** `@riverpod` annotations with `riverpod_generator`. Business logic lives in `Notifier` / `AsyncNotifier` classes.

**Rejected:** `StateNotifier` and `StateNotifierProvider`. Legacy API. Also rejected: `ChangeNotifier`, `setState` for anything crossing a widget boundary, and any global singleton service locator.

**Binding rules:**
- Riverpod lint rules run through `flutter analyze` (`riverpod_lint` via `analysis_server_plugin`). Warnings are errors.
  > **Status 2026-09-20 — not currently enforced.** `riverpod_lint` and `custom_lint` are not in `pubspec.yaml` (blocked by an analyzer-version conflict with the pinned `build_runner`/`freezed` toolchain). `flutter analyze --fatal-infos --fatal-warnings` runs the standard rule set plus the strict options in `analysis_options.yaml`, and is clean. The rules below are therefore enforced by review, not by tooling, until the lint stack is re-enabled during a dependency upgrade.
- Never read a provider inside `build()` outside of `ref.watch` / `ref.select`.
- Use `ref.watch(provider.select(...))` wherever a widget depends on one field of a larger object.
- Repositories are exposed as providers; widgets never construct a repository or DAO directly.

---

## ADR-3 — Navigation: `go_router`, 5 tabs, detail routes above the shell

**Decision:** `StatefulShellRoute.indexedStack` with 5 branches, in order:
`Home · Tracker · Library · Timer · Progress`. Home is index 0 and the start destination. Settings is an app-bar icon on Home, not a tab. Do not add a sixth tab.

**Detail-route placement rule:**
- A **focused task** is a root-level route pushed over the shell (`parentNavigatorKey: _rootNavigatorKey`), full-screen, bottom bar hidden. This covers: active workout session, workout history detail, exercise detail page, running timer, settings.
- **Browsing within a tab's subject matter** stays inside the branch navigator. In v1 this is essentially empty, which is the correct and simpler outcome.

Rationale: the bottom bar must not be visible during an active set — a mistaken tap on "Library" mid-working-set is a serious UX failure. Hiding chrome also signals a mode the user must deliberately exit.

Accepted consequence: the Library tab does not remember its depth when you switch away. That is correct behaviour here.

**Binding rules:**
- Route paths and names are constants in `core/router/routes.dart`. No string literals at call sites.
- Navigation is by name, not path construction.

---

## ADR-4 — Timer is wall-clock based

**Decision:** The timer stores `startedAt` / `endsAt` as absolute timestamps and computes remaining time as `endsAt.difference(DateTime.now())` on every tick. State is recomputed from wall clock on resume.

**Rejected:** any design where elapsed time accumulates from `Ticker` frames or repeated `Timer.periodic` decrements. It drifts, and it stops when the screen locks — during exactly the 30 seconds the user is mid-interval.

**Binding rules:**
- `wakelock_plus` held for the duration of an active session, released on exit and on error paths.
- `flutter_local_notifications` schedules interval-boundary alerts on backgrounding; cancelled on foreground return.
- Notification permission is requested **in context** (first timer start), not at launch, and re-checked at each session start.
- If permission is denied, the timer still fully works: wakelock, audio and haptics continue. Show a one-time dismissible banner. A denied permission must never produce a silent failure.
- Audio cue files are preloaded at session start. Never construct a player per beep.
- iOS audio session is configured to **duck** the user's music, not interrupt it.

> **Known deviation, 2026-09-20.** No cue files are bundled (`assets/audio/` is empty), so `TimerAudioService` plays the OS alert sound via `SystemSound.play`. That satisfies "no player per beep" trivially but not "files are preloaded", and `docs/build-plan.md` notes `SystemSound` gives a click on Android and nothing useful on iOS (not yet checked on a device). `just_audio` is declared in `pubspec.yaml` but not yet used. Open in `TODO.md` (Week 2); the welcome screen and store listing say "sound", so this is user-visible.

> **Amended 2026-09-19 — boundary alerts need a declared receiver and exact alarms.** `flutter_local_notifications` does not declare its alarm receivers for the app: `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver` must be in the app's own `AndroidManifest.xml`, or scheduled alerts are dropped silently. `test/unit/android_manifest_test.dart` guards this. Boundary alerts use exact alarms when the OS allows them (`USE_EXACT_ALARM`; `SCHEDULE_EXACT_ALARM` capped at `maxSdkVersion=32`) and fall back to inexact delivery otherwise, which can be many seconds late. The boundary list is computed from the *running phase's own end* forward, each notification labelled with the phase that *starts*.

---

## ADR-5 — Nested form state is keyed by stable UUID, never by list index

**Decision:** The active workout draft (draft → exercises → sets) lives in a Riverpod `Notifier` as immutable `freezed` models. Every exercise and every set carries a generated UUID assigned at creation and never reused.

**Rejected:** centrally managed `List<TextEditingController>`. It leaks controllers, and deleting a middle set shifts indices so text values jump to the wrong rows.

**Binding rules:**
- Every lookup, update, and delete addresses an entity by `id`. Never by index.
- Each set row is a small `StatefulWidget` owning its own controllers, initialised from the model, disposing them in `dispose()`, pushing changes up via `onChanged` debounced 300ms.
- Widget `key` is the entity UUID (`ValueKey(set.id)`).
- The draft auto-persists. If the app is killed mid-workout, the draft is restored on next launch. Non-negotiable.
- The success snackbar appears only after the write transaction has committed — never optimistically.

---

## ADR-6 — Web is a first-class target; capabilities degrade, never throw

**Decision:** Every platform-specific capability sits behind a small interface in `core/services/` with a web implementation that is a safe no-op.

Applies to: `HapticFeedback` (no-op on web), local notifications, wakelock, file system paths, audio session configuration.

**Binding rules:**
- No `dart:io` import outside `core/services/`.
- Mouse-wheel scrolling, hover states, and keyboard focus order are verified on web.
- Layouts are checked at 360dp, 768dp, and 1440dp. No full-width stretched mobile layouts on desktop.

> **Amended 2026-09-19 (TODO.md decision D5) — web is not a launch target.** The title above is superseded for v1: launch is Android (iOS decided separately, D1). Web still builds, and the capability-degradation rules above still bind — they are what keeps the test suite and credential-free runs working — but web QA (IndexedDB persistence, `sqlite3.wasm`, hover/keyboard/wheel checks) is off the critical path, and web may ship post-launch as a demo at most. `driftDatabase(name: 'ironyx')` has no web options configured, so **web persistence is unverified**. Do not describe the web build as supported in store copy.

---

## ADR-7 — Export format is versioned from the first export ever written

**Decision:** Every export carries an envelope: `formatVersion` (integer, independent of app version), `dbSchemaVersion`, `appVersion`, `exportedAt`.

**Binding rules:**
- Import rejects unknown or newer `formatVersion` with a clear message.
- Older versions are migrated by explicit, tested migration functions.
- An unversioned file is never best-effort parsed.
- Import is transactional, preceded by a preview with entity counts and a confirmation, and takes an automatic pre-import snapshot.
- `ImportMode.replace` means *replace all user data while preserving a populated local exercise catalogue* — not a full database restore. The catalogue is seed content, not user data: a populated local catalogue survives a replace even if the backup carries an older or absent one, so importing a workout backup can never downgrade or wipe it. Restoring catalogue data itself (e.g. reverting a bad manual edit) is not a supported use of import; it is reseeded from `assets/data/exercises_seed.json` instead. A replace import that omits any *non-catalogue* table is rejected outright rather than treated as "this table is now empty" — a truncated or hand-edited file must never silently delete real user data with nothing to restore it from.

---

## ADR-8 — Accounts are optional, Supabase-backed, and hold no workout data

**Decision:** Email/password accounts via Supabase, behind an `AuthService` interface. Signing in is optional: the app is fully usable, forever, without one.

Supabase over Firebase Auth because it is a pure-Dart HTTP client and therefore works on all four targets — Firebase Auth has no Linux desktop support. Credentials arrive as `--dart-define=SUPABASE_URL=` / `SUPABASE_ANON_KEY=`, never committed.

Workouts, programs, templates and body metrics stay in local SQLite and are never uploaded. An account carries identity only. `profiles_table` holds the personal details (name, date of birth, sex, height) as a single row, associated with an account through a nullable `remote_user_id`.

> **Amended 2026-08-24 — temporary exception, opt-in.** "Never uploaded" is no longer unconditionally true. `features/backup/` adds an explicit, user-initiated **Account backup**: the whole database, as the ADR-7 export envelope, gzipped into one row per user in Supabase. Nothing uploads automatically and nothing uploads while signed out — it happens only when the user taps "Back up now".
>
> This exists because the app is in hands-on testing and a reinstall otherwise loses everything unless the tester remembered to export a file first. It is **backup/restore, not sync**: one slot per account, last write wins, restore replaces the device. There is no conflict rule because there is no merge.
>
> PLAN.md Phase 5 supersedes it with real per-table sync and rewrites this ADR properly. Until then the exception is written down here rather than left as a contradiction between the document and the code — the failure mode this whole file exists to prevent.
>
> Consequence to keep in view: Settings and the welcome screen still say workouts are local to the device. That is true by default and false once a user opts in, so the copy is scoped to "your workouts are stored on this device either way" rather than claiming nothing ever leaves.

> **Amended 2026-09-19 — account deletion and password recovery.** Both live behind the `AuthService` seam (`deleteAccount()`, `isPasswordRecoveryPending`, `passwordRecoveryRequests()`, `updatePassword()`), so the binding rules below are unchanged. Deletion calls the `delete_my_account()` security-definer RPC in `docs/cloud_backup_setup.sql`, which removes the caller's `backups` row and `auth.users` row — a client holding the anon key cannot delete an auth user any other way. It removes the *remote* account and backup only; local workouts stay until the user removes them in Settings → Data Management, and the confirmation copy says so. Store policy (Apple 5.1.1(v), Google Play) requires an in-app deletion path for any app with account creation; this is that path. Recovery arrives on `AuthChangeEvent.passwordRecovery` and routes to `/auth/reset-password`.

**Binding rules:**
- No `redirect` on the router for auth. A login wall is the one change able to stop a cold offline launch from reaching the dashboard.
- No `supabase_flutter` import outside `features/auth/domain/supabase_auth_service.dart` and `features/backup/data/supabase_cloud_backup_service.dart`. Everything else speaks `AuthUser` / `AuthFailure`, or `CloudBackupInfo` / `CloudBackupFailure`.
  > **Clarified 2026-09-20.** Three composition-root files also import the package, only to obtain the client: `main.dart` (`Supabase.initialize`), and the two controller files that build the service (`sb.Supabase.instance.client` in `auth_controller.dart` and `cloud_backup_controller.dart`). No Supabase *type* other than the client crosses into a controller or widget. Any new import beyond these is a violation.
- Implementations translate every transport and vendor error into `AuthFailure`; an unmapped exception reaching the UI is a bug. Network failure is its own kind, distinct from bad credentials.
- A build without credentials resolves `authServiceProvider` to `DisabledAuthService` and says so in Settings. This is ADR-6's degradation rule applied to accounts, and it is what keeps a credential-free `flutter run` and the whole test suite working.
- `AuthService.currentUser` is synchronous and reads only local storage, so an offline launch restores the session without a network call.
- Tests override `authServiceProvider` with a fake. Nothing in the suite touches the network.
- Body weight belongs to `body_metrics_table`, not to the profile. A second copy would immediately disagree with the Progress charts.

---

## Cross-cutting conventions

**Layering.** `presentation/` may import `domain/`. `domain/` imports nothing from `data/` or `presentation/`. `data/` implements interfaces declared in `domain/`.

**No magic values.** Colours, spacing (4/8/12/16/24/32), radii, durations, and strings come from `core/theme/` or the l10n files. A raw hex code or a bare `EdgeInsets.all(13)` in a feature file is a review rejection.

**Numbers use tabular figures.** Any font rendering live-changing digits (timer, weight, volume) must use tabular figures so digits do not shift width while counting.

**Definition of Done.** A task is complete when: zero analyzer warnings; unit tests exist for non-trivial logic and pass; loading, empty, and error states are handled; it works in light and dark; it works on Android, iOS, and Web or degrades with a documented reason; no hardcoded strings/colours/spacing; manually tested on a real device.

**Testing scope.** Golden tests are limited to the app shell, dashboard cards, and charts, in both themes, with pinned fonts on a single CI platform. Everything else uses ordinary widget tests. Broad golden coverage rots and trains the team to run `--update-goldens` reflexively.

**Est. 1RM.** Epley: `1RM = weight × (1 + reps / 30)`. Computed only for reps 1–12; returns weight directly at reps == 1. Always labelled "Est. 1RM" in the UI, never "1RM".

**Session volume.** `Σ (weight_kg × reps)` over completed, non-warmup sets.

---

## Instructions to an AI assistant reading this file

1. Do not introduce `StateNotifier`, `ChangeNotifier`, Hive, or index-keyed form state.
2. Do not invent package APIs. If unsure of a current API surface, say so rather than guessing.
3. Produce tests in the same response as the implementation, not afterwards.
4. Work on one milestone at a time. Do not scaffold ahead into future milestones.
5. If a request conflicts with an ADR above, say so before writing code.
