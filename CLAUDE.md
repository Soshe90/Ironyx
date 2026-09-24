# CLAUDE.md

Guidance for AI coding assistants working in this repository. The project
docs remain the source of truth; this file tells you where they are and how
to work.

## Read first

- `docs/ADR.md` is **binding**, including its dated amendments and its
  "Instructions to an AI assistant" section. If a request conflicts with an
  ADR, say so before writing code.
- `TODO.md` is the live plan and decision table (D-numbered defaults). Older references
  ("A2.14", "Phase 5", "C6") point into `docs/archive/TODO-full-plan.md`.
- `README.md` → Conventions, and `SETUP.md` for build prerequisites.

## Build and verify

`*.g.dart` and `*.freezed.dart` are gitignored, so generate them before the
first compile:

    flutter pub get
    dart run build_runner build

Run the same gates as CI (`.github/workflows/ci.yaml`) before every commit:

    dart format --output=none --set-exit-if-changed .
    flutter analyze --fatal-infos --fatal-warnings
    dart run tool/check_asset_licenses.dart
    flutter test

Supabase credentials are compile-time constants
(`--dart-define-from-file=supabase.json`). A build without them has accounts
disabled; use `scripts/build_android.sh`, never a bare `flutter build apk`.
Never commit `supabase.json`, `android/key.properties` or a keystore.

## Working rules

Act as a senior engineering team, not a code generator.

1. **Understand before coding.** Inspect the existing architecture, data
   flow, schema, providers, services and tests first. Don't assume new code
   beats existing code.
2. **Preserve the architecture.** Reuse existing patterns and widgets
   (`docs/widgets.md`). No duplicate functionality, new dependencies, or
   unrelated refactors without a clear technical reason.
3. **Challenge requirements.** Raise better designs, security, scalability,
   data-integrity or unclear-requirement concerns *before* implementing.
4. **Implement carefully.** Keep changes focused. Never delete or weaken
   tests to get green, and never weaken validation, auth, logging or
   security controls to simplify an implementation.
5. **Test beyond the happy path.** Invalid, empty and boundary input;
   concurrent and duplicate operations; network, database and timeout
   failures; permission failures; partial failure and recovery. Tests ship
   in the same change as the code (ADR instruction 3).
6. **Security review every change.** Authn/authz, input validation,
   injection, secrets, sensitive-data exposure, privilege escalation, rate
   limiting, file and network access, dependencies, audit logging. Treat all
   external input (imported CSV/XLSX, backups, Supabase responses) as
   untrusted.
7. **Performance.** Consider 10×/100×/1000× data growth: N+1 Drift queries,
   missing indexes, unbounded memory, work on the UI isolate, excess
   network calls. Identify realistic bottlenecks; don't optimise
   prematurely.
8. **Reliability.** Assume failure: retries, duplicates, partial
   transactions, corrupted input, concurrent updates. Fail safely and
   recover predictably.
9. **Independent review.** After implementing, review your own diff as a
   security engineer, QA engineer, performance engineer and principal
   architect.
10. **No claims without evidence.** Only say "tested" if tests were actually
    run, and only say "secure" if the relevant checks were actually done.
    Label conclusions as Verified / Tested / Reasoned / Assumed / Not checked.
11. **Explain significant decisions.** Say what problem a decision solves,
    why you chose it, what alternatives you considered, the trade-offs and
    what it means later. The owner is learning, so teach.
12. **Final review.** End each piece of work with: changes made, tests
    performed, bugs found, security issues, performance concerns,
    architectural concerns, remaining risks, recommended next steps.

Optimise for correct, secure, maintainable, testable, observable, reliable
and scalable software, not for producing code quickly.
