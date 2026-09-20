# v2 ideas — parked

Nothing here enters v1. Write it down, then stop thinking about it.

"v1" means the launch build (`TODO.md`'s 12-week plan). Items marked
**→ v1.1** have been pulled into v1.1 *planning* (`TODO.md`, Week 11) — planning
only, no code before then.

## Original list

- Cloud sync / accounts — accounts and a manual single-slot backup shipped
  (ADR-8 amendment); real per-table sync stays here, gated on a D7 retention
  number (`PLAN.md` Phase 3 → 5).
- Social features, shared workouts
- Video demonstrations — the catalogue links out to YouTube for 48 exercises;
  no video is bundled or redistributed (`ASSETS-LICENSE.md`)
- Wearable integration (Health Connect / HealthKit) — **→ v1.1**
- Nutrition tracking
- Plate calculator
- Apple Watch / Wear OS companion
- Plan periodisation (5/3/1, GZCLP templates)

## Added from the launch plan and audits (2026-09-20)

Deferred deliberately, with where the reasoning lives:

- **Premium tier** (backup / sync / deeper analytics; subscription and/or
  lifetime) — planning only; no IAP code until a D7 number exists.
  `PLAN.md` Phase 6, `TODO.md` C12.
- **Referral program, public REST API, free premium for reviewers** — dropped
  from the launch schedule (`TODO.md` C12); no API exists.
- **Web build as a product** — demo at most, post-launch (decision D5). Needs
  `sqlite3.wasm` / `drift_worker.js` and an IndexedDB persistence check first.
- **iOS launch** — fast-follow in Q1 2027 unless D1 says otherwise.
- **Expanded built-in program library; deeper analytics on Progress phases 0–4;
  competitor import beyond the current XLSX** — **→ v1.1**.
- **Animated exercise demos and a static SVG anatomy view** — rejected for v1
  on licensing and offline-scope grounds (`TODO.md`, ADR-8 media decision);
  ExerciseDB (AGPL-3.0) and Gym Visual-derived sets are ruled out as sources.
- **Muscle & Motion-style media-first library reskin** — not adopted.
- **1RM projection band** — deferred until there is a minimum-sample-size
  policy; the UI does not extrapolate from a thin series.
- **Per-month bucketing for all-time charts** — a multi-year history draws
  hundreds of weekly bars; group by month when it matters
  (`TODO.md` Progress Phase 0 follow-up).
- **"Also remove local data" offered on sign-out** — an open UX decision
  (`TODO.md` A2.2), to be reconciled with ADR-8.
- **Brzycki as an alternative 1RM formula** (settings toggle) — suggested in
  `docs/build-plan.md`, not built.
- **Recorded / designed timer sounds, or a choice of sound packs** — the timer
  now ships three synthesized tones (`scripts/build_timer_cues.py`); nicer
  sounds are polish, not a v1 need.
- **Terms of service** — not required by either store for a free app with no
  IAP; revisit if accounts or premium change that.
