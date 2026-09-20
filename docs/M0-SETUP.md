# M0 — Repo & Tooling Runbook

> **Historical — do not re-run.** The project was created long ago and M0 is
> done. For a working checkout use `SETUP.md`. Things in this runbook that
> are no longer true:
>
> - The bundle id is fixed: `com.soshe90.ironyx` (changed twice before first
>   publish; it is permanent once Play sees it). `--org com.yourdomain` below
>   is a placeholder from the original template.
> - `dart run build_runner build --delete-conflicting-outputs`: the installed
>   `build_runner` no longer accepts that flag (conflict deletion is the
>   default). Use `dart run build_runner build`.
> - `dart run custom_lint` and the `riverpod_lint` / `custom_lint` /
>   `golden_toolkit` dev dependencies are not in the project (ADR-2 status note).
> - A `linux/` folder also exists (plugin registrant files only, from a
>   desktop-enabled Flutter run); only Android, iOS and Web are targets.

**Time:** ~half a day
**Exit:** CI green on an empty project, tagged `v0.0.1-scaffold`
**Rule:** do not write a single line of feature code in M0. The only deliverable is a project that builds, lints, tests, and has its decisions written down.

---

## 1. Preflight

```bash
flutter --version          # stable channel
flutter doctor -v          # resolve every ✗ before continuing
```

Fix `flutter doctor` completely now. An unsigned Android toolchain or a missing CocoaPods install will cost you an hour at M7 instead of five minutes today.

---

## 2. Create the project

```bash
flutter create \
  --org com.yourdomain \
  --project-name ironyx \
  --platforms=android,ios,web \
  --description "Offline-first workout tracker" \
  ironyx

cd ironyx
```

> ⚠️ **`--org` is effectively permanent.** It becomes the Android `applicationId` and the iOS bundle identifier. Changing it after a store submission means a new app listing and no upgrade path for existing users. Use a reverse-domain you actually control. Same for `--project-name`: lowercase with underscores, no hyphens, and it cannot be a Dart reserved word or a pub package name you might later depend on.

```bash
git init
git add -A
git commit -m "chore: flutter create"
git branch -M main
git checkout -b develop
```

---

## 3. Dependencies

Use `pub add` rather than hand-editing `pubspec.yaml` — it resolves versions that are current *today*, which is more reliable than any version list I could give you.

```bash
flutter pub add \
  flutter_riverpod \
  riverpod_annotation \
  go_router \
  drift \
  drift_flutter \
  sqlite3_flutter_libs \
  path_provider \
  fl_chart \
  freezed_annotation \
  json_annotation \
  shared_preferences \
  flutter_local_notifications \
  wakelock_plus \
  just_audio \
  intl \
  uuid \
  collection

flutter pub add dev:build_runner \
  dev:riverpod_generator \
  dev:riverpod_lint \
  dev:custom_lint \
  dev:drift_dev \
  dev:freezed \
  dev:json_serializable \
  dev:flutter_lints \
  dev:mocktail \
  dev:golden_toolkit

flutter pub add dev:integration_test --sdk=flutter
```

Then commit `pubspec.lock`. It is not generated noise — it is what makes your build reproducible.

**Verify before trusting:** check each package's pub.dev page for platform support and last-publish date. `golden_toolkit` in particular has had maintenance gaps; if it looks stale, `flutter_test`'s built-in `matchesGoldenFile` is sufficient for the narrow golden scope in the ADR. `drift_flutter` is the current recommended way to open a database connection — confirm the setup against drift's own docs at M2, since that API changed relatively recently.

---

## 4. Run the scaffold

Put `scaffold.sh` in the project root and run it:

```bash
bash scaffold.sh
```

It creates the full `lib/core` + `lib/features` skeleton, `analysis_options.yaml`, `.github/workflows/ci.yaml`, `docs/v2-ideas.md`, and appends generated-file rules to `.gitignore`. It is idempotent and will not overwrite anything that already exists.

Then the important part:

```bash
cp /path/to/ADR.md docs/ADR.md
```

---

## 5. Register assets

Add to `pubspec.yaml` under `flutter:`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/data/
    - assets/audio/
```

---

## 6. Generated files: ignored, not committed

The scaffold gitignores `*.g.dart` and `*.freezed.dart`, and CI regenerates them.

**Tradeoff, so you can disagree deliberately:** ignoring them means a fresh clone needs `build_runner` before it compiles, and IDE errors look alarming until you run it. Committing them means every rename produces a large diff and generated files conflict on merge. For a solo project, ignoring is the better trade — you never hit generated-file merge conflicts. If you add collaborators later, revisit.

```bash
dart run build_runner build --delete-conflicting-outputs
```

Run this once now, purely to confirm the toolchain works end to end. It should succeed with nothing to generate.

---

## 7. Verify locally

```bash
dart format .
flutter analyze --fatal-infos --fatal-warnings
dart run custom_lint
flutter test
flutter build apk --debug
flutter build web --release
```

**Expect the default counter app to trip a few of the strict lints** — the generated `main.dart` and `widget_test.dart` were not written against `always_declare_return_types` and friends. Two options:

1. Fix the handful of warnings now (five minutes), or
2. Reduce `main.dart` to a bare `runApp(const ProviderScope(child: MaterialApp(home: Scaffold())))` and delete the counter test.

Option 2 is cleaner, since M1 replaces all of it anyway. Do not weaken `analysis_options.yaml` to make the counter app pass — that defeats the point of setting strictness on day one.

---

## 8. README

Replace the generated README with something a future you can use:

```markdown
# Ironyx

Offline-first workout tracker. Flutter — Android, iOS, Web.

## Setup
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

## Architecture
See `docs/ADR.md`. It is binding. Read it before writing code, and paste it
into the context of any AI-assisted session.

Summary: Drift (SQLite) for persistence · Riverpod codegen for state ·
go_router with a 5-branch StatefulShellRoute · wall-clock timer ·
UUID-keyed nested form state · web-safe capability services.

## Commands
    dart run build_runner watch --delete-conflicting-outputs
    flutter analyze --fatal-infos --fatal-warnings
    dart run custom_lint
    flutter test --coverage
```

---

## 9. Push and tag

```bash
git add -A
git commit -m "M0: scaffold, tooling, CI, ADRs"
git push -u origin develop
git tag v0.0.1-scaffold
git push --tags
```

Watch the Actions tab. **Do not start M1 until CI is green**, including the web build — web is the step most likely to surprise you, and finding out at M7 is far worse than finding out now.

---

## Exit checklist

- [ ] `flutter doctor` clean
- [ ] Project created with the correct, permanent `--org`
- [ ] `main` and `develop` branches exist
- [ ] All dependencies added; `pubspec.lock` committed
- [ ] Folder skeleton in place
- [ ] `docs/ADR.md` present
- [ ] `analysis_options.yaml` strict; zero warnings locally
- [ ] `dart run custom_lint` passes
- [ ] `build_runner` completes successfully
- [ ] Debug APK and release web build both succeed
- [ ] CI green on push
- [ ] `docs/v2-ideas.md` exists and everything out of scope is parked there
- [ ] Tagged `v0.0.1-scaffold`

---

## Then M1

Start a **fresh** AI session. First message: paste `docs/ADR.md` in full, then ask for M1 only — design system, theme, router shell, 5 tabs, shared widgets. Do not let it scaffold ahead into the database or the tracker.
