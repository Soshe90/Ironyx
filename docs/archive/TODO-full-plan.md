> **ARCHIVED 2026-09-20 — superseded by the two-day finish plan in `/TODO.md`.**
> This is the full 12-week launch plan, the post-launch roadmap (formerly `PLAN.md`)
> and both engineering audits, kept unchanged for reference. Older references in
> the code and docs ("TODO.md A2.14", "Roadmap Phase 5", "C6", "D1", "Week 2"...)
> point at items in this file.

# Ironyx — TODO and plan

This checklist captures the production-hardening work identified during the architecture, data-integrity, UX, and release-readiness audit. Prioritize data safety before polish.

> **Active tracker: [Launch plan — 12 weeks](#launch-plan--12-weeks)** (reviewed 2026-09-19;
> documentation reconciled against the code 2026-09-20 — see the Week 0 hygiene item).
> Below it: the [Roadmap after launch](#roadmap-after-launch--release-platforms-and-revenue)
> (release, platform and revenue phases and their gates — formerly `PLAN.md`,
> merged into this file 2026-09-20), the first engineering audit (Priority 0–4, Progress feature track,
> validation checklist — essentially complete) and
> [Audit 2](#audit-2--production-readiness-review-2026-08-28). Their open items
> are pulled into the launch plan as gates; tick them here, not twice.

**Contents**

1. [Launch plan — 12 weeks](#launch-plan--12-weeks) — decisions D1–D5, week-by-week schedule, go-live gate, success criteria, risk register.
2. [Roadmap after launch](#roadmap-after-launch--release-platforms-and-revenue) — release, platform and revenue phases 0–6 with their gates, the numbers, roadmap decisions, working notes.
3. First engineering audit — [Priority 0–4](#priority-0--backup-and-data-integrity-safety), the [Progress feature track](#feature-track--smarter-progress-analytics), the [validation checklist](#validation-checklist-before-release).
4. [Audit 2 — production readiness review](#audit-2--production-readiness-review-2026-08-28).

## Launch plan — 12 weeks

**Reviewed 2026-09-19.** Source: *IRONYX Workout App — 12-Week Execution Plan
v1.0* (same date; not stored in the repo, and the three guides it points at —
`FITTRACK_DASHBOARD_REDESIGN_GUIDE.md`, `DASHBOARD_REDESIGN_SUMMARY.md`,
`IRONYX_STRATEGIC_PLAN.md` — do not exist in it; "FitTrack" is a pre-rename
leftover). **Where this section disagrees with the source, this section wins.**
Owner tags as in the [Roadmap](#roadmap-after-launch--release-platforms-and-revenue): **dev** = code, **acct** = only the account holder
can do it.

**Not verified in this review — read before trusting any "done":**

- `flutter analyze` / `flutter test` were **not run** in the review session (no
  Flutter SDK on PATH). **Since run, 2026-09-19:** analyze clean, 393 passed,
  1 skipped (see Week 0). **Re-run 2026-09-20 on the full working tree:**
  analyze `--fatal-infos --fatal-warnings` clean; `flutter test` **423 passed,
  1 skipped, 0 failed**; `dart format` clean on `lib/` and `test/`. The
  uncommitted diff (79 files) is analyzed and tested, but not yet committed;
  it has been seen on an Android 15 emulator only, never on a physical device.
- Store-policy facts below (Play closed-test rule, Apple/Play field limits,
  account-deletion rules) are from the reviewer's knowledge as of early 2026.
  Re-check each against the live Play Console / App Store Connect docs before
  scheduling around it. Items that hinge on this are marked **(verify)**.
- Repo-state claims were checked against the tree on 2026-09-19; evidence is in
  the cross-check table.

### Verdict

The shape (polish → QA → submit → launch → grow) and the ~460 h budget are
sound, and the plan's arithmetic checks out (85 + 107 + 124 + 152 = 468 h;
per-week blocks sum to their weeks). But it was written as if from a blank app,
and it collides with the repo and with store rules in four places that would
each cost a week if found late. Those are **B1–B4**. Roughly half of the
"Week 1–2 dashboard redesign" already exists.

### Blockers — fix the plan around these

| # | Blocker | Evidence | Resolution (scheduled below) |
|---|---|---|---|
| **B1** | **No in-app account deletion.** Apple (guideline 5.1.1(v)) and Google Play both require an in-app deletion path — plus, for Play, a web URL — for any app that lets users create an account **(verify)**. | `PRIVACY_POLICY.md` says the app "provides sign-out but not an in-app account-deletion button"; grep of `lib/` for `deleteAccount`/`deleteUser` finds nothing. A client holding the anon key cannot delete an `auth.users` row, so this needs server-side work. | W1–W2: `delete_my_account()` security-definer RPC + Settings UI + policy update. |
| **B2** | **Google Play closed-testing gate.** A new personal developer account must run a closed test (12 opted-in testers, 14 continuous days at time of writing) before it may apply for production **(verify)**. The plan has no closed test, no tester recruitment, and creates the Play account in Week 5. | Roadmap Phase 2 already lists "Closed testing track first" as `acct`; the 12-week plan dropped it. Working back from a Tue Nov 17 go-live, the 14-day clock must start by **Mon Oct 12**. | W0: create account. W2: recruit 15–20 testers. W3: closed test live. |
| **B3** | **Telemetry contradicts what the app promises.** The plan adds Amplitude + Firebase + Sentry in Week 2. | `PRIVACY_POLICY.md`: "no analytics SDK, no advertising SDK, and no crash-reporting service". `STORE_LISTING.md`: "does not run ads or analytics". Play Data Safety and Apple App Privacy must match the shipped binary. No such dependency is in `pubspec.yaml`. | **D2** below. Recommended: Sentry only, wired through the existing `reportError()` seam, with the policy and listing copy updated **first**. No Amplitude/Firebase. |
| **B4** | **iOS is not on a launchable path.** The plan submits to the App Store in Week 5. | No Mac, no Apple Developer enrolment, no signing/TestFlight pipeline. iOS `AppIcon` and `LaunchImage` are still the initial-commit Flutter template (`AppIcon 1024` ≠ `assets/branding/ironyx-icon-1024.png`; launch images are 68-byte placeholders). The CI `ios` job (`--no-codesign`) has never run. Roadmap Phase 4 gates iOS on the $99 decision. | **D1** below: explicit go/no-go on Mon Oct 5. Default if not "go": Android-first, iOS fast-follow in Q1 2027. |

### Corrections applied to the source plan

| # | Source plan says | Reality | Correction |
|---|---|---|---|
| C1 | "Monday, September 26"; PH "Monday Nov 14"; "Wed Nov 15" | 2026-09-26 and 2026-11-14 are **Saturdays**; Nov 15 is a Sunday. Weekday names look copied from an older calendar. | Re-anchored to Mon–Sun weeks: **Week 1 = Mon Sep 28**, Week 12 = Dec 14–20 (contains Dec 18). The old "Sept 19–26" prep week becomes **Week 0 (Sep 21–27)**. |
| C2 | "Launch Date: December 18" | The schedule goes live in Weeks 8–9 (Nov) and uses Dec 18 as the *evaluation* date. Week 8 also launches on Product Hunt **before** Week 9 releases to the stores. | Store go-live **Tue Nov 17** (W8); Product Hunt **Wed Nov 18**, only after the app is live; **Fri Dec 18 = measurement date**. |
| C3 | Effort "300–400 h"; phase headers 50–70 / 60–80 / 80–100 / 70–90 | Sections sum to 468 h. Headers sum to 260–340 h. | One number: re-baselined estimate **≈ 460 h** (table at the end). |
| C4 | "primary teal"; hero number "48px teal" | `AppColors.seed = 0xFF2D6BFF` (electric blue). Icon + `web/manifest.json` use navy `#0B1628` / teal `#38D6C0`. **The app theme and the icon disagree.** | **D3.** |
| C5 | Title "Ironyx — Precision Workout Tracking" (35 chars); subtitle "Offline-first fitness tracking for athletes" (43); Play category "Sports"; "Free with in-app purchases"; "PEGI 3"; icon "JPG" | App Store name and subtitle max 30 chars each; Play title max 30 **(verify)**. There is no IAP. Play rates via the IARC questionnaire. `STORE_LISTING.md`'s "Ironyx: Offline Workout Log" (27) is fine. Play also requires a **1024×500 feature graphic**, which the plan omits. | Category **Health & Fitness** on both. Price **Free** (declare IAP only when one exists). Icon **PNG, no alpha**. Draft an iOS name/subtitle ≤ 30 each. *(Drafted 2026-09-20 in `docs/STORE_LISTING.md`: name 19, subtitle 29 characters.)* |
| C6 | Marketing copy: "sync later", "Open APIs (integrations coming soon)", "60fps, minimal battery drain", "Free with IAP" | No sync exists (one manual backup slot). No API exists. 60 fps / battery are unmeasured (device profiling still open). | Reuse the honest copy already in `docs/STORE_LISTING.md`. Delete the three claims until true. |
| C7 | Reddit/HN/forum posting plan | r/fitness is known to restrict self-promotion; every sub has its own rules **(verify each)**. New accounts created a week before posting trip spam filters. HN "Show HN" needs something people can try and must not ask for upvotes. An "IPA backup" is not a thing — TestFlight is the fallback. Influencer freebies need FTC-style disclosure. | Community accounts move to **W4** and participate genuinely for 3+ weeks. Read each sub's rules before drafting. Stagger posts across days. |
| C8 | 500 downloads, 50 DAU, 4.5★ by Dec 18; "50K users, $10K MRR" in a year | Roadmap Phase 3: months 1–3 with no marketing = 0–100 downloads; year-1 "low thousands" is *good*; 500 paying subs needs 10–25K active users. 50 DAU from ~500 installs is 10% DAU/install. A rating from < 10 reviews is noise. The plan's "95%+ coverage" conflicts with `build-plan.md` M7 (≥ 70% on `domain/` + `data/`); CI enforces no threshold. | Keep the plan's numbers as **targets**, add **floors** (D4), and use 70% coverage on `domain/`+`data/`. |
| C9 | Test on iPhone SE / 14 Pro, Safari (Mac), Chrome (Mac) | Dev machine is Windows; no Mac. | W0 device inventory; emulators/cloud devices for the rest. iOS/Safari rows apply only if D1 = go. |
| C10 | "Localization check (if multi-language)"; "Health kit / camera / storage" permissions | App ships **English + Arabic (RTL)**. No HealthKit, camera or storage permission is used; manifest = `INTERNET, VIBRATE, WAKE_LOCK, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED`. | RTL, Arabic screenshots and 200% text-scale QA are in scope. Permission check becomes the notification flow (Android 13+/iOS) + file-picker export/import. |
| C11 | Privacy policy in Week 4; website in Weeks 5–6 | Both stores need a **public policy URL** before any track goes live (closed test included), and Play needs the account-deletion URL. | Minimal site (policy + support email + delete-account page) in **W2**. Full landing page stays W5. |
| C12 | Week 9 API docs; Week 11 "implement premium check", referral program, free premium for reviewers; "Free with IAP" | No REST API, no IAP dependency; cloud backup is an interim single-slot blob Roadmap Phase 5 says to delete rather than extend. Roadmap Phase 3 gate: no Phase 5/6 work until there is a D7 retention number. | **Dropped from the schedule.** Week 11 keeps premium as *planning only*. |
| C13 | Name/domain | The Roadmap's status history (2026-09-15) cleared the name on Play only, after one rename on Sep 15. | W0: check App Store name availability, do a trademark search, confirm the domain **before** spending on assets. |
| C14 | Launch Nov 14–21, judge Dec 18 | US Thanksgiving is Thu Nov 26 (W9). January is the peak month for fitness apps and falls after the Dec 18 review. Apple review has historically slowed late December **(verify)**. | No big pushes Nov 26–27. Plan a **January ASO/creator push** in the Q1 roadmap; don't read Dec 18 as the final verdict. |

Two backend items the source plan never mentions, both **(verify)**: Supabase's
built-in email sender is rate-limited and not meant for production traffic
(sign-up confirmation mail is the first thing a launch spike breaks — configure
custom SMTP), and free-tier projects pause after roughly a week of inactivity
(a paused project silently breaks sign-in and backup for every new user). Both
are scheduled in W2.

### Cross-check — plan item vs repo (2026-09-19)

| Plan item | Repo state | Verdict |
|---|---|---|
| `hero_metric_card.dart` (count, goal bar, trend, quick actions) | `_TodayCard` + `_WeekBody` in `dashboard_page.dart`: volume hero, trend chip, sparkline, sessions/streak/last week, Start/Resume + Start-from-program. No goal progress bar — but `profiles.weekly_session_target` (schema v9, default 3) already exists to feed one. | **Partial** |
| `metric_card.dart` / `metric_grid.dart` | `summary_card.dart`, `_OneRmCard`, `_BodyWeightCard` in a fixed 2-up row. No 1/2/3-col grid. | **Partial** |
| `weekly_breakdown_calendar.dart` (M–Su) | Nothing. (`HistoryCalendar` exists on the Tracker — reusable day-cell logic.) | **Missing** |
| Six providers named `weeklyWorkoutCountProvider` … | Eight per-card providers exist under different names (`dashboardLastWorkout`, `…LastTimerSession`, `…LibrarySummary`, `…MostLoggedOneRM`, `…LatestBodyMetrics`, `…WeeklyVolume`, `…WeeklyFrequency`, `…WeekSnapshot`). Genuinely missing: average duration, per-day breakdown. | **Partial** |
| `DashboardData` freezed model | **Conflicts** with the design: one provider per card so "one failing card must never blank the whole dashboard" (`dashboard_providers.dart`, `build-plan.md` M6). | **Drop** |
| `dashboard_skeleton_loader.dart`, empty state, retry | Per-card `LoadingShimmer` + `ErrorView` exist; "Ready to train" CTA + `WeekSnapshot.hasHistory`. Zero-data new-user state not verified on screen. | **Done** (verify empty state) |
| Responsive 1/2/3 col | `Breakpoint` compact / medium 768 / expanded 1200 in `core/widgets/responsive.dart`; dashboard uses it only for the button row and sparkline width. WIP diff uncommitted. | **Partial** |
| Dark mode | `ThemeModeNotifier`, `theme_mode_test.dart`. | **Done** |
| App icon / splash | Android launcher, web icons, `web/manifest.json`, `assets/branding/*` updated 2026-09-18. iOS `AppIcon` + `LaunchImage` = template; Android splash = default `launch_background.xml`; `web/index.html` still says "A new Flutter project" / title `ironyx`; no icon/splash generator configured. | **Partial** |
| Store graphics | None. `test/golden/*.png` are test renders, not store screenshots. No feature graphic. | **Missing** |
| Store description | `docs/STORE_LISTING.md`: Play title/short/full drafted, ASO keywords, screenshot order. No iOS listing. | **Partial** |
| Analytics + Sentry | Neither in `pubspec.yaml`. `lib/core/error_reporting.dart` `reportError()` is the single integration seam, `kDebugMode`-gated. | **Conflict** (B3) |
| Privacy policy | `docs/PRIVACY_POLICY.md` (2026-09-17). Not hosted. Stale on deletion (B1) and on telemetry if D2 ≠ none. | **Partial** |
| Terms of service | None. Not required by either store for a free app with no IAP; decide whether accounts justify one. | **Optional** |
| Signing / AAB | Keystore + `key.properties` exist (gitignored, **not backed up**). `scripts/build_android.sh bundle` builds an AAB. Release shrinking off, and CI never builds a release variant (A2.11). `pubspec` version `0.1.0+1`. *(Updated 2026-09-20: shrinking + obfuscation are now on and `pubspec` is `1.0.0+1`; the uncommitted `ci.yaml` adds a shrunk, obfuscated release-APK build. **The keystore and `key.properties` are not on this Windows machine** — see Week 0.)* | **Partial** |
| Unit / widget / golden tests | 367 passing as of 2026-08-29 (**423 as of 2026-09-20**). 12 screen goldens incl. `dashboard.png` + `dashboard_tablet.png` (dated Aug 22 — **stale against the WIP diff**). The 12 h "golden tests" block is mostly a refresh. | **Mostly done** |
| Offline / persistence / crash recovery | Unit-covered; real-device validation still open (Priority 2). | **Partial** |
| Accessibility audit | Code-level pass done; TalkBack / VoiceOver open. | **Partial** |
| Data export "JSON, CSV" | Both in Settings → Data Management. | **Done** |
| Web target | `flutter build web` passes. `driftDatabase(name: 'ironyx')` has no web options and `web/` holds no `sqlite3.wasm` / `drift_worker.js`; runtime persistence never verified. | **Unverified** (D5) |
| Website, newsletter, PH assets, blog | Nothing. | **Missing** |
| API docs, premium, referral, IAP | Nothing, by design. | **Drop** (C12) |
| v1.1 "workout templates" / "analytics dashboard" | Templates + 3 built-in programs exist; Progress analytics Phases 0–4 shipped. | **Rewrite v1.1 scope** |

### Decisions — defaults apply if you do nothing

| # | Decision | Recommended default | Decide by |
|---|---|---|---|
| D1 | iOS at launch or fast-follow? | **Fast-follow** unless enrolled + a build host chosen (Codemagic vs Actions) by Oct 5. If "go", iOS tasks below apply. | Mon Oct 5 |
| D2 | Telemetry: none / Sentry only / Sentry + analytics | **Sentry only**, scrubbed (no email, no exception text), policy + listing updated first. Use Play Console / App Store Connect for installs and retention. | Fri Oct 2 |
| D3 | Brand primary: teal (icon, web manifest) or blue (theme seed) | **Teal** — it is what users see on the home screen; move `AppColors.seed` to match and re-check contrast. | Sun Sep 27 |
| D4 | Success floors (proposed — edit) | See "Success criteria". | Sun Sep 27 |
| D5 | Web as a launch target? | **No** — post-launch demo at most. Removes the wasm/IndexedDB verification and web QA from the critical path. | Sun Sep 27 |

- [ ] D1 decided (due Mon Oct 5)
- [ ] D2 decided (due Fri Oct 2)
- [x] D3 decided 2026-09-19: **teal**. Move `AppColors.seed` to match the icon/manifest teal (`#38D6C0`) in the Week 1 brand task, then re-check 4.5:1 contrast in light and dark.
- [x] D4 decided 2026-09-19: floors accepted as proposed in "Success criteria".
- [x] D5 decided 2026-09-19: **web is not a launch target** (post-launch demo at most). Drops web QA and the wasm/IndexedDB check from the critical path; `web/index.html` title fix and the Priority 2/3 web items stay parked.

### Week 0 — Mon Sep 21 – Sun Sep 27 · prep (≈ 6 h)

Lead-time items go first: they take calendar days regardless of effort.

- [ ] **acct** Create the Play Developer account ($25) and start identity verification.
- [ ] **acct** Back up `android/upload-keystore.jks` + `android/key.properties` to two durable locations. Losing the keystore means never updating the listing. **(2026-09-19: neither file exists in `F:\Ironyx\android` on this Windows machine — both are correctly gitignored and untracked, and a search of the repo and `C:\Users\musta` (depth 4) found only debug/OneDrive keystores. They were created on another machine or environment. Locate the original before anything else; if it is gone, generate a new upload key now, before the first Play upload, and back it up at creation. **Rechecked 2026-09-20: still absent** — `android/*.jks` and `android/key.properties` do not exist, so `build.gradle.kts` silently falls back to the debug key and any release build made here is debug-signed and not uploadable. Recipe: `SETUP.md` §5. **Account holder, 2026-09-20: the original is lost — generate a new upload key.** That is safe only because nothing has ever been uploaded to Play under the old one. Still to do, by the account holder (it needs passwords only they should choose): run the `keytool` command in `SETUP.md` §5, back up `upload-keystore.jks` + `key.properties` to two durable places *immediately*, then build the AAB and confirm it is release-signed (`keytool -printcert -jarfile <aab>` must show the new key, not the Android Debug key). Deadline: before the Mon Oct 12 closed-test upload; do it in Week 0–1 so signing problems surface early.)**
- [ ] **acct** Clearance: App Store name availability, trademark search for "Ironyx", domain (`ironyx.app` / `ironyx-app.com`) — before any asset spend (C13). *(2026-09-19 DNS lookup: `ironyx.app`, `ironyx-app.com`, `getironyx.com`, `ironyx.io`, `ironyx.fit` return NXDOMAIN, i.e. probably unregistered; `ironyx.com` gave a DNS server failure — inconclusive. NXDOMAIN is not proof of availability: confirm at a registrar. App Store name and trademark still need a manual search.)* Also record **who made the app icon / mark and how** (own design, commissioned, or tool-generated) in `ASSETS-LICENSE.md` — it is not written down anywhere, and ownership affects both the trademark search and what can be claimed.
- [ ] **acct** Device inventory: which real Android/iOS devices exist; what needs emulators or cloud devices (C9).
- [x] **dev** Baseline on a machine with Flutter: `flutter analyze`, `flutter test`. **2026-09-19, Flutter 3.47.5 / Dart 3.13.4 (stable), installed at `C:\src\flutter` and added to the user PATH:** `flutter analyze --fatal-infos --fatal-warnings` — no issues; `flutter test` — **393 passed, 1 skipped, 0 failed** (the skip is the golden review harness), including the WIP dashboard diff and the three tests added the same day. The new 1440 dp layout test was confirmed to fail with "BoxConstraints forces an infinite height" against the original `stretch` row. **Formatting (re-checked 2026-09-19 later the same day): clean** — `dart format lib test` reports 0 changed on 283 files, so the 5-file drift listed earlier no longer reproduces. Goldens were not regenerated. `flutter pub get` warns that Windows plugin builds need Developer Mode (symlinks); irrelevant to analyze/test, needed for `flutter build`/`run` on this machine. **Re-run 2026-09-20 (same SDK, full working tree): analyze clean (97 s), `flutter test` 423 passed, 1 skipped, 0 failed (≈ 56 s), `dart format` 0 changed on 284 files.** The earlier counts in this file (393 / 397 / 408) were each correct for the day and tree they were taken on; 423 is current.
- [x] **dev** `tool/check_asset_licenses.dart` **failed on Windows** (found and fixed 2026-09-20): 602 false "unreferenced image ships in the APK" errors, one per image, because it built paths with `\` (from `listSync`) and compared them with the seed's `/` paths. No licence, source, hotlink or missing-file error was ever reported, and Linux CI was unaffected — a tooling bug, not a licensing problem. Fixed by normalising separators; now passes locally ("301 exercises, 602 images, all cleared") and a deliberately orphaned image is still caught (exit 1, then removed).
- [ ] **dev** Docs hygiene, found in the 2026-09-20 read-through — **fixed in the docs, but the underlying items are still open:** (a) ~~`assets/audio/` is empty and the timer plays `SystemSound.alert`~~ **fixed the same day** — real cues bundled and wired (Week 2); (b) ~~`just_audio` is declared but unused~~ **now used** by the cue player; (c) `freezed` is pinned to a **prerelease** (`4.0.0-dev.3`) — fine for code generation now, worth a look before a long freeze; (d) `riverpod_lint` / `custom_lint` are not in the project, so ADR-2's lint rule is enforced by review only.
- [ ] Read this section end to end; confirm 40 h/wk; block the calendar Sep 28 – Dec 20; place ICAO prep (target Oct 31) around W4.
- [ ] Set up tracking: this file is the tracker (no second tool).
- [x] Decide D3, D4, D5. (2026-09-19 — see Decisions.)

### Week 1 — Sep 28 – Oct 4 · dashboard finish + brand (≈ 40 h)

**Dashboard** (≈ 22 h — roughly half of the source's 40 h; the rest exists)
- [ ] **dev** Once baseline is green: finish and commit the WIP diff (gradient Today card, two-up buttons at ≥ 768, `IntrinsicHeight` removal). *(2026-09-20: baseline is green — 423 tests. The uncommitted tree is much larger than the dashboard: 79 files covering the brand/theme, splash and icons, account deletion, password recovery, timer-notification fixes, R8 shrinking and CI. Only the Markdown docs have been committed so far; the code diff still needs to go in as logical commits.)*
> **Cross-check 2026-09-19 (code read first; analyze + tests run afterwards — see the Week 0 baseline).** The
> ticks below were checked against the uncommitted diff. Two ticks were
> overstated and are fixed in the same pass:
> the desktop row used `Row(crossAxisAlignment: stretch)` inside a
> `SliverToBoxAdapter` (unbounded height → layout assertion at ≥ 1200 dp), and
> the weekday strip bucketed days in UTC, so a workout just after local
> midnight showed on the wrong day. The Arabic `dashboardStatStreak` label was
> also changed (المواظبة → التتابع) in the same diff with no note here — confirm
> that is intended.

- [x] **dev** Goal progress bar in the hero from `weekly_session_target` (sessions x / target). (`_SessionGoal`; target clamped to 1–7, default 3.)
- [x] **dev** Mon–Sun weekly breakdown (filled = trained) + per-day provider. Implemented as private `_WeeklyBreakdown` / `_WeekdayCell` in `dashboard_page.dart` plus `dashboardWeekdayDistributionProvider`, not a standalone `weekly_breakdown_calendar.dart`. Reuses `WorkoutDao.watchWeekdayDistribution` (Monday-first, zero-filled); it now takes a `utcOffset` and the dashboard passes the device offset. RTL mirroring comes from `Row`; not seen on screen.
- [x] **dev** Average-duration metric (provider + card), backed by completed workouts with recorded durations.
- [x] **dev** `Breakpoint.expanded` layout with a constrained content width (closes Priority 3 "desktop layouts use constrained widths"). Two-column primary row (Today 2 : This week 1) and a secondary row (Progress 2 : Recent 1) inside `PageBody`'s 1100dp cap. Rows use `start` alignment. Not run at 1440 dp on a real window.
- [x] **dev** Spacing via `AppSpacing` only. (Spacing yes; icon/bar/marker sizes — 28, 18, 8, 56 and `_dayMarkerSize = 32` — are literals.)
- [x] **dev** Verify `WeekSnapshot.from` after Phase 0 zero-fill in `WorkoutDao._fillWeekGaps`. The snapshot now documents that gaps are zero-filled while an empty result still means no history.
- [x] **dev** First look on a device (2026-09-19, Android 15 emulator, Pixel 6, release APK, 1080×2400): welcome screen and dashboard render in the teal theme, light mode, no overflow or exceptions. The Today gradient card, two stacked buttons, "Progress"/"Recent" sections and bottom nav all look right. **Empty state:** a new user sees "No training in the last 8 weeks" *instead of* the session-goal bar and weekday strip (they live inside `_WeekBody`, which only renders with history) — decide whether a zero-data user should see "0 / 3" and an empty strip. **Resolved 2026-09-19:** they now do — the "no recent training" text stays and the goal bar and empty weekday strip sit under it (tested; not re-seen on the emulator). **Not yet seen:** the goal bar and weekday strip with data, dark mode, Arabic/RTL, tablet/desktop widths.
- [ ] **dev** Tests. Added and **passing (2026-09-19)**: `dashboard_page_test.dart` (goal + trained-day marker; 1440 dp layout does not throw), a `utcOffset` case in `progress_analytics_dao_test.dart`, and `dashboard_providers_test.dart` coverage for empty snapshots, current/previous week selection, streaks, and series length. **Added 2026-09-19 (passing):** empty-history state, week-card error state, and an Arabic/RTL check that Monday sits right of Sunday in the strip. Still open: refresh `dashboard.png` + `dashboard_tablet.png` and add a desktop golden.

**Brand** (≈ 8 h)
- [x] **dev** Apply D3: `AppColors.seed` → `0xFF38D6C0` (2026-09-19). Measured 4.5:1 contrast on the generated schemes, both themes (onPrimary/primary 6.43 light, 7.74 dark; primary on surface 6.13 / 10.81; container text 7.27; secondary, tertiary and error on surface ≥ 6.15; lowest is the light selected-nav label on its 16% indicator, 4.61). `fromSeed` mutes the seed, so the in-app primary is `#006B5E` (light) / `#83D5C6` (dark), not the icon's vivid `#38D6C0`. **Still open:** eyeball both themes on a device; `AppColors.gain` (`#3DD68C` green) now sits close in hue to the teal primary — check trend chips vs primary elements; `chartSeries[0]` is still the old blue `#2D6BFF` (left alone — decide whether series 1 should follow the brand); regenerate goldens.
- [x] **dev** Typography pass: centralized modern heading, title, label, and metric hierarchy in `app_typography.dart` and `app_theme.dart` (2026-09-19). Shared cards, navigation, buttons, progress indicators, and app bars now use the refreshed visual system. Device/golden review remains open below.
- [x] **dev** iOS `AppIcon` set (2026-09-19). The 1024 master has pre-rounded, transparent corners (App Store rejects both), so it was rebuilt as an opaque square: the icon's own `#0B1628 → #122D48` diagonal gradient underneath, the artwork composited on top. All 15 sizes are 24-bit RGB PNGs, no alpha. **Not seen in Xcode or on a device** (no Mac).
- [x] **dev** Branded splash (2026-09-19). Android: navy `launch_background.xml` with the mark (≤ 11) and `values-v31` / `values-night-v31` `windowSplashScreenBackground` + `AnimatedIcon` (12+). iOS: `LaunchImage` 1x/2x/3x mark on transparent + navy storyboard background. Navy in both light and dark by design. **Not visually verified:** the splash could not be captured on the emulator (Android 15), and iOS not at all.
- [x] **dev** Android adaptive icon (2026-09-19): vector foreground + gradient background + monochrome layer for Android 13 themed icons; legacy PNGs stay for API < 26. **Seen on the Pixel 6 / Android 15 emulator launcher** with the circular mask: mark inside the safe zone. Mark colours are sampled from `ironyx-icon-1024.png`, not the SVG — the SVG's gradient renders differently from the shipped PNG.
- [x] **dev** Notification small icon: the timer notification used `@mipmap/ic_launcher` (full colour → grey blob on Android 5+, and a name-only lookup R8 can strip). Now a dedicated monochrome `@drawable/ic_notification` plus `res/raw/keep.xml`. Not yet seen in a real notification.
- [ ] **dev** Fix `web/index.html` title/description only if D5 = yes.

**Account deletion — B1** (≈ 10 h, continues into W2)
- [x] **dev** Design: `delete_my_account()` security-definer RPC removing the caller's `backups` row and `auth.users` row; added to `docs/cloud_backup_setup.sql` (2026-09-19). The Supabase dashboard still needs to run it.
- [x] **dev** Client behind the `SupabaseAuthService` seam; Settings → Account → "Delete account" with typed confirmation; sign out + `unlinkAccount` after success. Added English/Arabic copy and widget coverage (2026-09-19).
- [x] **dev** Local data decision documented in the confirmation copy and client flow: account deletion removes the remote account and cloud backup, but keeps local workouts until the user explicitly removes them from Data Management (2026-09-19).

### Week 2 — Oct 5 – Oct 11 · trust + release plumbing (≈ 42 h)

- [ ] **acct** **D1 go/no-go (Mon Oct 5).** If go: enrol in Apple Developer Program and pick the build host.
- [ ] **dev/acct** Finish B1: l10n en + ar and tests are complete; `PRIVACY_POLICY.md` already describes in-app deletion (checked 2026-09-19); still open: test account deletion end to end with a real account. **SQL execution in the Supabase dashboard is treated as complete per account-holder confirmation (2026-09-19).**
- [ ] **dev** D2 outcome: if Sentry — `sentry_flutter` wired **only** inside `reportError()`, `beforeSend` scrubbing, release tagging, symbol upload plan (pairs with A2.11 obfuscation) and a deliberate test crash; update policy + listing copy in the same change. If none — nothing to build.
- [x] **dev** Password recovery (2026-09-19): `AuthService` gained `isPasswordRecoveryPending`, `passwordRecoveryRequests()` and `updatePassword()`; `SupabaseAuthService` listens for `AuthChangeEvent.passwordRecovery` from construction; `app.dart` pushes the new `/auth/reset-password` route on the event or, for a cold start from the link, on the first frame; `ResetPasswordPage` validates like sign-up. New failure kinds `samePassword` and `recoveryExpired` (en + ar; expired offers "Request a new link"). 8 widget tests against the fake. **Not run against a real Supabase project or a real reset email** — needs `supabase.json` and the redirect URL below. The cold-start path relies on the SDK delivering the initial link after the service is created (it arrives on `uriLinkStream`, so it should) — confirm on a device.
- [ ] **acct** Supabase: add `com.soshe90.ironyx://login-callback` to Redirect URLs; move Site URL off `http://localhost:3000` (Roadmap Phase 1 — still unchecked, and deep-link confirmation is broken without it). Confirm email confirmation + rate limits are on server-side (Audit 2 open question). Configure custom SMTP and check free-tier pause behaviour **(verify)**. **A custom SMTP provider becomes a second data processor for users' email addresses** — `PRIVACY_POLICY.md` currently says Supabase is the only third party, so name the provider there (and in the Data Safety / App Privacy answers) in the same change.
- [ ] **dev/acct** Publish the minimal site: policy, support email, delete-account instructions (C11). Record the public URL here and use it in the store forms.
- [ ] **dev** *(2026-09-19: **partly done** — shrinking + resource shrinking on, `proguard-rules.pro` (Gson / `flutter_local_notifications`), `--obfuscate --split-debug-info=build/symbols/<version>` in `scripts/build_android.sh`, version `1.0.0+1` (`kAppVersion` matched). A shrunk, obfuscated release **APK** (89.6 MB, was 94.9 MB) built in ~2.5 min and booted to the welcome screen on the Android 15 emulator with no crash. **Timer notifications — two real bugs found and fixed, one decision open (2026-09-19, Pixel 6 / Android 15 emulator).** *Symptom:* Tabata started, app backgrounded, alarms fired ("5 wakes 5 alarms") but no notification ever posted; an unshrunk build did the same, so R8 was cleared. *Root cause 1 — the manifest never declared the alarm receiver.* `flutter_local_notifications`' own manifest carries permissions only; its README requires the **app** to declare `ScheduledNotificationReceiver` (and `ScheduledNotificationBootReceiver`). Without it Android delivers the alarm broadcast to a component that does not exist and drops it silently, so **scheduled timer notifications had never worked on any device** and nothing survived a reboot despite `RECEIVE_BOOT_COMPLETED` (and the privacy policy) saying otherwise. Both receivers are now declared, non-exported, with `test/unit/android_manifest_test.dart` guarding them (fails against the old manifest). *Root cause 2 — off-by-one in `TimerController._rescheduleBoundaries`:* it skipped the running phase's own end (so the first, most urgent boundary was never scheduled) and labelled each notification with the phase that had just *ended*. Fixed; 5 new tests, three of which fail against the old code. *Verified on the emulator with the shrunk release build:* `Rest phase / Rest starts now`, then `Work phase / Work starts now`, right channel, small icon = the new `ic_notification`. *Still open — exact alarms:* boundary alarms are inexact (`inexactAllowWhileIdle`), and the first boundary arrived **14 s late** on a 20 s work phase (longer than a Tabata rest). `PlatformNotificationService` now asks the OS (`canScheduleExactNotifications`) and uses exact alarms when allowed, falling back to inexact — so it is safe with or without the permission. Measured with `USE_EXACT_ALARM` temporarily declared (then removed): delivery **0.10–0.39 s** after the scheduled time (`window=0`). **Decision (account holder, 2026-09-19): declare `USE_EXACT_ALARM`** (plus `SCHEDULE_EXACT_ALARM` capped at `maxSdkVersion=32` for Android 12/12L); the manifest comment records the rationale and the fallback — if Play rejects the declaration, delete both lines and the code degrades to inexact. `PRIVACY_POLICY.md` permission list updated to match. **Play risk is not gone, only accepted:** the permission is restricted to apps whose *core function* is an alarm/timer/calendar **(verify against the live Play policy)**, so the Play Console exact-alarm declaration must cite the interval/rest timer and will be reviewed — see the Week 3 forms item. Not yet covered: no *completion* notification exists (`showCompletion` is never called; the last phase's end is unannounced when backgrounded), and everything above is emulator-only — a physical device is still required. **Still open:** the AAB, a real device, and archiving `build/symbols/` — it is gitignored, so each store upload's symbols must be copied somewhere durable or that build can never be symbolicated.)* Enable release shrinking (A2.11) **and** run the release AAB on a real device the same day (`scripts/build_android.sh bundle`). Set a real version (`1.0.0+N`). *(2026-09-19: an unshrunk, debug-signed release **APK** — 94.9 MB, all ABIs — built in ~5 min and launched on an emulator; shrinking, the AAB and a real device are still open. Windows build note: the pub cache (`C:`) and the repo (`F:`) are on different drives, which breaks Kotlin incremental compilation — build with `flutter build apk -P kotlin.incremental=false`, or move `PUB_CACHE` onto `F:`. Gradle also auto-installed NDK 28.2, Build-Tools 36 and Platform 34 into `C:\Android\Sdk`.)*
- [x] **dev** Timer sound cues — ADR-4 gap found and **closed 2026-09-20**. No audio files were bundled (`assets/audio/` held only `.gitkeep`), so `TimerAudioService` played `SystemSound.alert`, while the welcome screen ("with sound and haptics"), the settings toggle and the store copy all promised sound. Now: three cues (`countdown`, `transition`, `complete`) synthesized by `scripts/build_timer_cues.py` (deterministic, stdlib-only, so ours outright — `ASSETS-LICENSE.md`), preloaded once into one `just_audio` player each and reused; the OS alert is only the fallback if a cue cannot load or play; nothing audio-related can fail the timer. New `TimerCuePlayer` seam + `test/unit/timer_audio_service_test.dart` (12 tests: one player per cue and none per beep, fallback, never throws, dispose and re-use); full suite **435 passed, 1 skipped**, analyze clean. **Verified on the Android 15 emulator with the shrunk, obfuscated release APK (no Supabase credentials):** the cue files are in the APK; 3 ExoPlayers initialise at session start (so R8 did not strip just_audio/media3); logcat shows the countdown ticks (5,292 frames = 0.12 s), transitions (14,773 = 0.33 s) and the completion cue (29,546 = 0.67 s) each taking audio focus, playing and releasing it; the phase-change notification ducks our stream (`onAudioFocusChange(-3)`); the 3 players are released when the session ends and 3 fresh ones are created for the next; no `FATAL`, `MissingPlugin` or `ClassNotFound`. **Not done:** hearing it on a physical device (an emulator log proves playback happened, not that it sounds right or loud enough), and anything on iOS (audio-session ducking there is unchecked; `SystemSound` was reportedly silent on iOS, so this may be a real improvement, unverified).
- [x] **dev** Countdown timing quirk (fixed 2026-09-20). Live countdown values now round up at sub-second boundaries for both the displayed digits and cue selection; ordinary elapsed-duration formatting still truncates. Added formatter regression coverage.
- [ ] **dev** Physical-Android validation, Priority 2: force-kill recovery, timer across background/lock, wakelock release, notification reschedule.
- [ ] **acct** Recruit 15–20 closed testers (opt-in list / Google Group); 12 must stay opted in for 14 days **(verify)**.
- [ ] **dev** Store assets round 1: real-device screenshots (light + dark, English + Arabic), 1024×500 feature graphic.

### Week 3 — Oct 12 – Oct 18 · QA + closed test starts (≈ 45 h)

- [ ] **acct** **Mon Oct 12: upload the signed AAB to a Play closed-testing track.** Complete the app-content forms: Data Safety, health-apps declaration, IARC rating, target audience, ads = none, policy URL, account-deletion URL, **and the exact-alarm permission declaration** (`USE_EXACT_ALARM` — justify it by the interval/rest timer; if Play pushes back, drop the two manifest lines, nothing else changes).
- [x] **dev** Measure coverage; target ≥ 70% on `domain/` + `data/` (not 95%). **2026-09-19: 70.9%** (`domain/` 74.3%, `data/` 0/71 lines) excluding generated code; whole `lib/` 68.2%. Optimistic: lcov only lists files some test imports. The 0% files are the two Supabase adapters (`supabase_auth_service.dart`, `supabase_cloud_backup_service.dart`) — no network seam. Next-lowest: `edit_workout_notifier` 56%, `progress_providers` 59%, `active_workout_notifier` 78%. Full suite that run: 408 passed, 1 skipped.
- [ ] **dev** Unit/widget tests for any W1–W2 change; layouts at 360 / 768 / 1440 dp.
- [ ] **dev** Manual QA on real devices: touch targets, scrolling, dark mode, Arabic/RTL, 200% font scale, notification permission flow (grant + deny fallback, per M4).
- [ ] **dev** Import/export failure + recovery scenarios manually tested (validation checklist).
- [ ] **dev** Log bugs; triage tester feedback as it arrives.
- [ ] **acct** *(if D1 = go)* Create the App Store Connect record, signing set-up, first TestFlight build.

### Week 4 — Oct 19 – Oct 25 · fix + performance (≈ 45 h)

- [ ] **dev** Fix all critical bugs from W3 + tester reports; push updated closed-test builds.
- [ ] **dev** Measure, on a real mid-range device, release/profile build: cold start to dashboard < 2 s, cached < 0.5 s, memory < 100 MB, 60 fps scroll. Also time the first-launch seed on a real file-backed DB (A2.6 was inconclusive in-memory).
- [ ] **dev** Regenerate the golden matrix (320/375/768/1024/1440 × loading/data/empty/error where the harness supports it).
- [ ] **dev** TalkBack pass (and VoiceOver if D1 = go); status not by colour alone; focus order if web ships.
- [ ] **dev** Crash simulation + recovery, offline mode, data persistence across restart.
- [ ] **acct** Start genuine participation in the target subreddits/Discords (C7). No promotion yet.
- [ ] **dev** *(if D1 = go)* TestFlight pipeline green; iOS device checks (audio ducking, notifications, wakelock); iOS backup-exclusion (A2.3 open item); App Privacy questionnaire.

### Week 5 — Oct 26 – Nov 1 · production access + listings (≈ 40 h)

- [ ] **acct** Confirm the 14-day closed test completed (≈ Oct 26); apply for Play production access. Note the review time **(verify)**.
- [ ] **dev/acct** Full landing site: hero, features, screenshots, FAQ, support, newsletter (with a privacy notice), analytics only if it matches D2. (≈ 20 h)
- [ ] **acct** Finish Play listing (title ≤ 30, short ≤ 80, full ≤ 4000, Health & Fitness, ≥ 4 screenshots, feature graphic).
- [ ] **acct** *(D1 = go)* iOS listing: name ≤ 30, subtitle ≤ 30, keywords, description, support + privacy URLs, screenshots at the current required sizes **(verify)**, age rating.
- [ ] **acct** Product Hunt page prepared: title, tagline, thumbnail, description, maker bio, demo link; line up early supporters.
- [ ] Fix anything from the final week of closed-test feedback.

### Week 6 — Nov 2 – Nov 8 · submissions (≈ 40 h)

- [ ] **acct** Submit Play production (consider a staged rollout).
- [ ] **acct** *(D1 = go)* **Submit iOS by Wed Nov 4** — leaves room for a first-round rejection before Nov 17.
- [ ] **dev** Launch playbook: store messaging, social posts, Reddit threads, newsletter email, support plan.
- [ ] **dev** First blog post drafted; 3–5 social teasers.

### Week 7 — Nov 9 – Nov 15 · monitor + content (≈ 36 h)

- [ ] **acct** Check review status daily. Rejection → resubmit within 24 h. Fallback if iOS is rejected: launch Android-only, iOS follows.
- [ ] **dev** Publish blog post (Medium, Dev.to, own site).
- [ ] **dev** Community groundwork continues; research subreddit rules for each planned post.
- [ ] **Fri Nov 13 — go/no-go gate:** see "Go-live gate" below.

### Week 8 — Nov 16 – Nov 22 · launch (≈ 40 h)

- [ ] **acct** **Tue Nov 17: release to Play** (and the App Store, if approved — use manual release so both go live together).
- [ ] **dev** Same day: install from the store on a clean device and run sign-up, deep-link confirmation, backup and restore. A store-signed build can differ from a local one (Play App Signing key vs deep links / Supabase).
- [ ] **acct** **Wed Nov 18: Product Hunt** (12:01 AM PT), answer every comment all day. Only after the app is live.
- [ ] **acct** **Thu Nov 19 onward:** Reddit (per-sub rules, staggered, genuine), optional Show HN, Dev.to / Indie Hackers. Draft post copy from `docs/STORE_LISTING.md`'s wording, not the source plan's appendix (which is not in the repo and contains C6's three false claims).
- [ ] Respond to every review; fix and ship hotfixes fast; collect early-adopter feedback.

### Week 9 — Nov 23 – Nov 29 · initial metrics (≈ 30 h)

- [ ] Track downloads, installs/uninstalls, ratings, crash-free rate daily (Play Console; Sentry if D2).
- [ ] Read every review; list top bugs and top requests.
- [ ] Quiet on Thu Nov 26 – Fri Nov 27 (US holiday).
- [ ] ~~API documentation~~ **removed** (C12). Use the time for an in-app feedback/support path and an FAQ.

### Week 10 — Nov 30 – Dec 6 · learn + patch (≈ 36 h)

- [ ] Analyse: downloads, DAU, D1/D7 retention, crash-free %, rating.
- [ ] Ship v1.0.1 for the top three bugs; update listing text if it changed.
- [ ] Second blog post ("Building Ironyx: offline-first architecture"); optional AMA; share testimonials with permission.
- [ ] Draft v1.1 roadmap from real feedback.

### Week 11 — Dec 7 – Dec 13 · growth + planning (≈ 30 h)

- [ ] Growth experiments (short-form video, threads, stories); micro-creator outreach with disclosure.
- [ ] Ask beta testers for reviews and testimonials.
- [ ] v1.1 scope, rewritten: expanded built-in program library, Health Connect / Apple Health, deeper analytics on top of Progress Phases 0–4, competitor import beyond the current XLSX. Estimate, sequence, backlog.
- [ ] Premium — **planning only**: tier, price, what is gated. **No code**, no IAP, until Roadmap Phase 3's D7 number exists.

### Week 12 — Dec 14 – Dec 20 · review (≈ 30 h)

- [ ] **Fri Dec 18: compile the final numbers** (below) against the success criteria.
- [ ] Q4 retrospective: what went well, what to improve, Q1 priorities. Include a **January acquisition push** (C14).
- [ ] Lock the Q1 roadmap; sprint schedule; help/contractor needs; Year-2 budget.
- [ ] Thank early users and testers; take time off.
- **Next review:** Thu Dec 31, 2026.

### Go-live gate — Fri Nov 13

Ship on Nov 17 only if **all** are true; otherwise slip a week and say so here.

- [ ] Play production access granted and the build is approved.
- [ ] Closed-test crash-free rate ≥ 99.5% over the last 7 days.
- [ ] No open critical or data-loss bug.
- [ ] B1 (account deletion) works end to end on a real account.
- [ ] Privacy policy, Data Safety and listing copy all match the shipped binary (B3).
- [ ] Release-variant build (shrunk) smoke-tested on a real device.
- [ ] Keystore backed up; Supabase redirect URL + SMTP verified.
- [ ] *(D1 = go)* iOS approved; otherwise Android-only launch is confirmed as the plan.

### Success criteria — measured Fri Dec 18

Proposed floors are mine (D4) — edit them. Targets are the source plan's.

| Metric | Floor | Target | Stretch |
|---|---|---|---|
| Live in Play | required | required | — |
| Live in App Store | (D1) | required if D1 = go | — |
| Downloads | 100 | 500 | 1,000 |
| Rating (min. 10 reviews) | ≥ 4.0 | ≥ 4.5 | ≥ 4.7 |
| Crash-free sessions | ≥ 99% | ≥ 99.5% | ≥ 99.8% |
| Daily active users | 10 | 50 | — |
| Dashboard load (real mid-range device) | < 3 s cold | < 2 s cold, < 0.5 s cached | — |
| Critical bugs at launch | 0 | 0 | — |
| Product Hunt launched | yes | yes | top 10 |
| First blog post | yes | yes | — |
| Q1 2027 roadmap locked | yes | yes | — |

Retired from the source plan: "2–5% premium conversion" (no premium exists),
"500 newsletter subscribers" and "1K website visitors" (vanity; keep as
optional), "1,000 waitlist" and "First premium subscriber" stretch goals.

### Risk register

| Risk | Sev. | Prob. | Mitigation |
|---|---|---|---|
| Play production access delayed (closed-test gate, B2) | 🔴 | High if unplanned | Account in W0; testers W2; test live by Oct 12; go/no-go Nov 13 |
| Store rejection for missing account deletion (B1) | 🔴 | High if unfixed | Built and verified in W1–W2 |
| Policy / Data Safety / binary mismatch (B3) | 🔴 | Med | One change updates code, policy and listing together |
| iOS not ready by Nov 4 | 🟡 | Med–High | D1 go/no-go; Android-first fallback is pre-agreed |
| Release-variant crash after enabling shrinking (A2.11) | 🔴 | Low–Med | Real-device smoke test in W2, not at release-cut |
| Signup email fails under launch traffic / paused Supabase project | 🟡 | Med **(verify)** | Custom SMTP; keep project active or upgrade before W8 |
| Keystore lost | 🔴 | Low | Two backups in W0 |
| Design not polished enough | 🟡 | Low | Half the dashboard already exists; time-box W1 |
| Bugs found in QA | 🟡 | 30% | 50% slack in W4 |
| Low downloads | 🟡 | 25%+ | Floors in D4; January push (C14); read as ASO signal, not failure |
| Burnout (40+ h/wk) | 🔴 | 20% | Weekends off; W9/W11/W12 are lighter by design |
| ICAO exam conflict | 🟡 | 15% | Prep by Oct 31 (in W4); schedule the exam after launch |

### Time tracking

Planned hours are a **re-baselined estimate**, not the source plan's (C3). Fill
in Actual on Sundays; add a two-line note (done / blocked / next).

| Week | Dates | Focus | Planned h | Actual h | Notes |
|---|---|---|---|---|---|
| 0 | Sep 21–27 | Prep, lead-time items | 6 | | |
| 1 | Sep 28–Oct 4 | Dashboard, brand, B1 start | 40 | | |
| 2 | Oct 5–11 | B1, telemetry, release plumbing | 42 | | |
| 3 | Oct 12–18 | QA, closed test live | 45 | | |
| 4 | Oct 19–25 | Fixes, performance, a11y | 45 | | |
| 5 | Oct 26–Nov 1 | Prod access, listings, site | 40 | | |
| 6 | Nov 2–8 | Submissions | 40 | | |
| 7 | Nov 9–15 | Monitor, content, gate | 36 | | |
| 8 | Nov 16–22 | **Launch** | 40 | | |
| 9 | Nov 23–29 | Metrics, reviews | 30 | | |
| 10 | Nov 30–Dec 6 | Patch, learn | 36 | | |
| 11 | Dec 7–13 | Growth, v1.1 planning | 30 | | |
| 12 | Dec 14–20 | Review, Q1 roadmap | 30 | | |
| | | **Total** | **460** | | |

### Weekly status template

```markdown
## Week N (dates)
### Done            - task (h)
### In progress     - task (ETA)
### Blocked         - blocker → mitigation
### Lessons
### Next week's top 2
### Time            planned / actual / variance
```

---

## Roadmap after launch — release, platforms and revenue

*Formerly `PLAN.md`, merged into this file on 2026-09-20 so there is a single
tracker. Its content is kept in full; only the sentences that pointed between
the two files and four decision rows that duplicated the launch plan's
Decisions table were removed. Phase numbers below are this section's own;
elsewhere in the repo they are cited as "TODO.md Roadmap Phase N".*

The path from "works on my phone" to "published, and possibly earning". Each
phase has a **gate**: a question to answer before the next phase is worth
starting. The gates matter more than the checkboxes — most of the ways this
goes wrong involve building Phase 5 before Phase 3 has said whether anyone
comes back.

Related, which this section does not duplicate:

- The **Launch plan — 12 weeks** above is the dated schedule, and the audits
  below hold the engineering hardening (imports, data integrity,
  accessibility, device validation) — still the source of truth for code
  quality work.
- `docs/ADR.md` — architecture decisions. Several items below **amend** an
  ADR; those are called out, because changing one quietly is how a codebase
  stops matching its own documentation.
- `docs/v2-ideas.md` — features deliberately deferred.

Owner column: **dev** = code, **acct** = something only the account holder can
do (dashboards, payments, legal). The `acct` items are the ones that silently
block everything else.

---

### Roadmap status — 2026-09-20

Published: no. Platforms: Android only (iOS builds are unverified — no Mac).
Revenue: none. Users: 1. `flutter analyze` clean; `flutter test` 423 passed,
1 skipped, 0 failed.

**The active tracker is now the "Launch plan — 12 weeks" section above** (Sep 28 –
Dec 20; Android store go-live Tue Nov 17). It schedules most of the `acct`
and `dev` items below and adds four blockers this section did not have:
in-app account deletion (done in code), the Play closed-testing gate, the
telemetry-vs-privacy-policy contradiction, and iOS not being on a launchable
path. Where the two disagree, the launch plan wins. Decisions taken since the
entries below (all in the launch plan's Decisions): brand primary is **teal** (D3), web is
**not a launch target** (D5), success floors accepted (D4); D1 (iOS) and D2
(telemetry) are still open.

Things this section used to say that have since changed: the catalogue is now
**301 exercises / 602 images** (seed v17), still all public domain; the
privacy policy is written (`docs/PRIVACY_POLICY.md`) but **not hosted**;
release shrinking and obfuscation are on; the account holder has decided to
declare `USE_EXACT_ALARM` for timer alerts (Play may reject it); and the
release keystore described in Phase 2 is **not present on the current
Windows machine** — locate it or generate a new upload key before the first
Play upload.

---

### Status history

#### 2026-08-24

Published: no. Platforms: Android only. Revenue: none. Users: 1.

**Asset licensing is resolved.** The catalogue was rebuilt from
free-exercise-db on 2026-08-24 — 150 exercises, 300 images, every one
public domain, and a CI check that fails the build if that stops being
true. See Phase 1 below.

The remaining Phase 1 blockers are cheap by comparison and mostly
`acct`: privacy policy, Play declarations, a real signing key, and the
bundle id — the last of which must happen **before** first publish.

**Update — 2026-08-29.** Phase 1's attribution item and Phase 4's three
`ios/` code gaps plus its CI job are done — see those sections for what
changed. Nothing here moves "Published: no" or "Platforms: Android only":
the iOS work is unverified without a Mac to actually run it, and the
remaining Phase 1/2 blockers are still `acct` items (privacy policy, Play
Developer account, Apple Developer enrollment) that need you, not more code.

> **Editorial note, 2026-09-20.** The two 2026-09-15 entries below were
> mangled by a global find-and-replace in commit `8417741` (they read
> "Ironyx → Ironyx" and "`com.soshe90.ironyx` → `com.soshe90.ironyx`"). The
> original wording is not in git history; the names below are reconstructed
> from the pre-rename tree (`pubspec.yaml` name `fittrack`, `applicationId`
> `com.soshe90.fittrack`, class `FitTrackApp`, Android label "FitTrack").

#### 2026-09-15

App renamed **FitTrack → Ironyx**. Cause: a Play Store check found
"FitTrack" already used by 5+ published apps, one with near-identical
positioning — a solo dev with no ad budget can't win ASO against exact-name
duplicates. Checked "Ironyx" has no existing Play Store listing *(Play only —
the App Store name, a trademark search and the domain are still open;
launch plan C13)*. Changed: Android manifest label, iOS `CFBundleDisplayName`,
both l10n `appTitle` strings (and every other user-facing "FitTrack" string —
export/import error messages, About screen copy), regenerated
`app_localizations_*.dart`, and the two widget tests asserting on the
literal displayed name. Initially left unchanged: the `applicationId` /
`namespace` (`com.soshe90.fittrack`), the Flutter package name (`fittrack`
in `pubspec.yaml`) and the internal `FitTrackApp` class.

**Same day.** On reflection, went further: the `applicationId` / bundle id
changed too, `com.soshe90.fittrack` → **`com.soshe90.ironyx`**, and the
package and class names followed (`ironyx`, `IronyxApp`). This is the second
and *last* time the bundle id can move — after first Play publish it's
permanent. Touched: `build.gradle.kts` (namespace + applicationId), the
Kotlin package directory (`MainActivity.kt` moved to
`.../com/soshe90/ironyx/`, `package` declaration updated),
`AndroidManifest.xml`'s intent-filter scheme, `ios/Runner/Info.plist`'s
`CFBundleURLTypes`, `ios/Runner.xcodeproj/project.pbxproj`'s
`PRODUCT_BUNDLE_IDENTIFIER` (6 occurrences across targets/configs), and
`lib/core/config/deep_links.dart`. **Consequence: the Supabase Redirect URLs
entry must be `com.soshe90.ironyx://login-callback`, not the old
`com.soshe90.fittrack://` one** — if the old one was already added to the
Supabase dashboard, add the new one instead (or in addition, harmlessly,
until nothing points at the old scheme). Verified with `flutter analyze`
(clean) and a `flutter clean` + debug APK build.

---

### Roadmap Phase 0 — Done 2026-08-23

- [x] Diagnosed `[auth] No Supabase credentials in this build`. Not a bug:
      `SupabaseConfig` reads compile-time `String.fromEnvironment` constants,
      so any launch without `--dart-define-from-file=supabase.json` ships
      with accounts off. Use `scripts/build_android.sh` or the committed IDE
      run configs.
- [x] Release APK built and verified (credentials confirmed present inside
      the binary, not just in the build command).
- [x] First-launch welcome screen — app intro, then create-account / sign-in
      / continue-as-guest. Shown once per install; reachable again from
      Settings → Account → Show welcome screen.
- [x] Guest copy tells the truth: workouts are local, uninstall deletes them,
      export from Settings. It does **not** claim an account protects data,
      because under ADR-8 it does not. Revisit when Phase 5 ships.
- [x] Auth deep link — `com.soshe90.ironyx://login-callback` is registered in
      the Android manifest and iOS `Info.plist`, and passed as `emailRedirectTo`
      on signup and password reset. The Supabase dashboard Redirect URLs
      allow-list and Site URL still require live-project verification.
- [x] Profile linking on any auth transition (`app.dart`). Confirming by deep
      link signs the user in without either auth screen on top, so neither
      was there to link the profile.

---

### Roadmap Phase 1 — Blockers before publishing

**Gate: is every asset in the APK legally ours to ship commercially?**

#### Exercise catalogue licensing — done 2026-08-24

The catalogue used to hold 86 exercises of which 41 sourced their images
from `liftmanual.com` / `mybodycreator` with `"license": null`. The
exposure was wider than those 41: 49 exercises **hotlinked** liftmanual
JPEGs at runtime, and 28 of the bundled PNGs were used by entries with no
`sources` record at all — unattributed and equally unlicensed. There was
no `ASSETS-LICENSE.md`, which is precisely why it stayed invisible.

- [x] **dev** — Source chosen: **free-exercise-db** (Unlicense / public
      domain, 873 exercises with images). No attribution burden, no
      share-alike, and its muscle and equipment vocabularies map cleanly
      onto the normalized schema.
- [x] **dev** — Catalogue rebuilt: **150 exercises, 300 images**, every
      one public domain and bundled locally. Zero hotlinks. All 71 old
      PNGs deleted from `assets/`, not merely unreferenced. *(Since grown
      to **301 exercises / 602 images** at seed v17 — commit `41dc429` —
      still every one public domain, 48 with a YouTube link; counts
      re-checked 2026-09-20.)*
- [x] **dev** — `scripts/build_exercise_seed.py` makes the rebuild
      repeatable rather than a one-off cleanup. Curation (which 150, and
      each one's `MovementPattern`, which upstream has no field for) is
      an explicit table in that script.
- [x] **dev** — `ASSETS-LICENSE.md` records every source, its licence,
      what it covers, and what we removed.
- [x] **dev** — `tool/check_asset_licenses.dart` runs in CI before the
      build and fails on a null licence, an uncleared source, a hotlinked
      image, a missing file, or an unreferenced image shipping in the APK.
- [x] **dev** — Surface attribution in-app. Not required by the Unlicense,
      so this is a courtesy, not a blocker. Settings -> About: an "Exercise
      data & photos" tile (a dialog crediting free-exercise-db, with a link
      to the source) and an "Open-source licenses" tile (`showLicensePage`,
      which also lists every package dependency's license automatically —
      the free-exercise-db credit is registered via `LicenseRegistry` in
      `main.dart` so it appears there too, not just in the dialog).

Ids were preserved by display name across the rebuild. This was a
correctness requirement, not tidiness: `name` carries a UNIQUE index and
`ExerciseDao.deleteOrphanedSeed` deliberately retains any exercise a
logged workout references, so minting a fresh id for a name still on disk
would raise `UNIQUE constraint failed: exercises_table.name` at seed time
— and only for users with training history.

Ten entries had no free-exercise-db equivalent and were dropped:
Bulgarian Split Squat, Kettlebell Swing (only the one-arm variant exists
upstream), Landmine Press, Pike Push-Up, Rear Delt Fly (Incline Bench),
and five near-duplicate cable-fly entries that had been sharing images.

#### Legal and store requirements

- [ ] **acct** — Privacy policy, publicly hosted. Mandatory for Play
      regardless of monetization. Must cover Supabase (email + auth) and
      anything added in Phase 2. *(2026-09-20: **written** —
      `docs/PRIVACY_POLICY.md`, last updated 2026-09-20 — covers Supabase,
      cloud backup, in-app account deletion and the permission list. **Not
      hosted anywhere**, so this box stays open; hosting is the launch plan's
      Week 2. It must be revised in the same change as any telemetry
      decision, D2.)*
- [ ] **acct** — Play Data Safety form.
- [ ] **acct** — Play health-apps declaration. Fitness data is a sensitive
      category with its own disclosure requirements.
- [ ] **acct** — Confirm Play supports merchant payouts in your country
      *before* building anything in Phase 6. This is a hard stop, not an
      inconvenience, and it is cheap to check now.

#### Technical tidy-up

- [ ] **acct** — Supabase dashboard → Authentication → URL Configuration →
      add `com.soshe90.ironyx://login-callback` to **Redirect URLs**.
      Until this is done the Phase 0 deep link does nothing: Supabase
      silently ignores an unlisted `redirect_to` and falls back to the Site
      URL. Also change Site URL off `http://localhost:3000`.
- [x] **dev** — Bundle id changed 2026-08-24 from the template placeholder
      `com.fittrack.fittrack` to `com.soshe90.fittrack`, and again on
      2026-09-15 (the rename) to the final **`com.soshe90.ironyx`**, across
      `android/app/build.gradle.kts` (namespace + applicationId), the Kotlin
      package directory and `MainActivity.kt`, `AndroidManifest.xml`'s
      intent filter, `ios/Runner/Info.plist`'s `CFBundleURLTypes`,
      `ios/Runner.xcodeproj/project.pbxproj`'s `PRODUCT_BUNDLE_IDENTIFIER`,
      and `lib/core/config/deep_links.dart`. The Supabase Redirect URLs
      entry above still needs the matching update (launch plan Week 2).
- [x] **dev** — Fix the 6 pre-existing test failures (5 in
      `library_page_test.dart`, 1 in `program_editor_page_test.dart`). Fixed
      during the Arabic localization work; `flutter test` now reports 337
      passed, 1 skipped, 0 failed (verified 2026-08-26).
- [ ] **dev** — Real-device validation from the Priority 2 audit section below: force-kill
      recovery, timer across backgrounding, wakelock release, notification
      rescheduling.

---

### Roadmap Phase 2 — Publish free on Play

**Gate: nothing here needs the app to be finished. Ship it and start
learning.**

- [ ] **acct** — Play Developer account. $25, one time.
- [x] **dev** — Signing keystore. Generated 2026-08-26:
      `android/upload-keystore.jks` (alias `ironyx_upload`), credentials in
      `android/key.properties` (both gitignored, neither backed up anywhere
      else yet). `build.gradle.kts` uses it for `release` builds when present,
      falling back to the debug key otherwise. **Still need to back the
      keystore up somewhere durable** — losing it means never updating this
      listing again once published. **2026-09-20: neither file exists on the
      current Windows machine** (rechecked; both were created elsewhere).
      Locate the originals first; if they are gone, generate a new upload key
      *before* the first Play upload, since nothing has been published under
      the old one, and back it up at creation (`SETUP.md` §5). **The account
      holder confirmed on 2026-09-20 that the original is lost**, so a new
      upload key is the plan; it has not been generated yet. Until then a
      release build here is debug-signed and cannot be uploaded.
- [ ] **dev** — Store listing: icon, feature graphic, screenshots, short and
      full description.
- [ ] **acct** — ASO. The highest-return free work available: title,
      keywords, screenshots. This is most of your organic discovery.
- [ ] **acct** — Closed testing track first, then production.
- [ ] **acct** — Play Console → Statistics for installs, uninstalls, active
      devices. Free, no code, and it counts guests — which Supabase cannot.
- [ ] **dev** — Decide whether to add Firebase Analytics. Needed to answer
      "which screens do people use, where do they quit". Costs a dependency,
      a privacy-policy section, and a consent story. Defer if unsure — Play
      Console covers the basics. *(2026-09-20: superseded by the launch plan's
      decision D2 — recommended **Sentry only**, scrubbed, no Firebase or
      Amplitude, and the policy/listing updated first. Still undecided;
      due Fri Oct 2.)*

**Counting users, for reference:**

| Question | Where |
|---|---|
| How many registered? | Supabase → Authentication → Users |
| How many installed / uninstalled? | Play Console → Statistics |
| What do they actually do? | Firebase Analytics, or a Supabase events table |

Note the blind spot: Supabase only ever sees signed-in users. Every guest is
invisible to it, by design (ADR-8).

---

### Roadmap Phase 3 — Learn retention — **the gate that matters**

**Gate: do people come back after a week? Do not start Phase 5 or 6 until
this has a number.**

Retention is the only metric that predicts whether monetization is worth
building. A paywall on an app nobody returns to converts zero users into zero
dollars, more slowly.

- [ ] **acct** — Measure D1 / D7 / D30 retention for at least 6 weeks.
- [ ] **acct** — Read every review. At this scale each one is a user
      interview you did not have to arrange.
- [ ] **acct** — Decide honestly: is D7 in the healthy range for fitness apps
      (roughly 10–25%), or below it?
  - **Below** → the product is the problem. Fix retention. Monetization is
    premature and will only obscure the signal.
  - **At or above** → proceed to Phase 4 / 5.

**Expected timeline, so the numbers are not a surprise.** A new fitness
tracker with no marketing typically sees single-digit to low-double-digit
downloads per month. Months 1–3: 0–100 downloads. Month 6: a few hundred
cumulative with good ASO. Year 1: low thousands cumulative is a *good*
outcome for a solo developer. This category is one of the most saturated on
the store — Strong, Hevy, Jefit, FitNotes all have years of ranking history.

---

### Roadmap Phase 4 — iOS

**Gate: is $99/year worth it before there is any revenue?** Nothing here
requires owning a Mac; only the compile does, and that can be rented by the
minute.

> **2026-09-20 — scheduling.** The launch plan makes this an explicit go/no-go
> (D1, Mon Oct 5) with **Android-first, iOS fast-follow in Q1 2027** as the
> default. iOS icon and launch images were replaced 2026-09-19 (opaque
> RGB icons, navy launch storyboard) but never seen in Xcode. Two caveats
> for whoever picks this up: the timer's sound cues (bundled 2026-09-20,
> played through `just_audio`) were checked on an Android emulator only —
> iOS audio-session ducking is unverified — and the iOS iCloud/iTunes
> backup-exclusion item (Audit 2 item A2.3) is still open.

- [ ] **acct** — Decide on the Apple Developer Program, $99/year. Without it
      a build cannot be installed on any physical iPhone. There is no free
      path that avoids this.
- [ ] **acct** — Pick the build host:
  - **GitHub Actions `macos-latest`** — repo is already on GitHub with a
    working `ci.yaml`. Public repos free; private repos bill macOS minutes at
    a 10× multiplier (~200 usable minutes on the free tier).
  - **Codemagic** — Flutter-native, ~500 free macOS minutes, far simpler code
    signing and TestFlight upload. Switch here if signing on Actions starts
    eating evenings.
- [x] **dev** — `ios/` is the untouched Flutter template. Three known gaps:
  - [x] `UIBackgroundModes` → `audio`. Without it iOS suspends the rest
        timer's audio the moment the app backgrounds. **The welcome screen
        currently advertises "runs in the background, with sound and
        haptics"** — true on Android, false on iOS until this is fixed.
        Added to `ios/Runner/Info.plist`.
  - [x] `flutter_local_notifications` iOS permission request and
        foreground-presentation setup, neither of which Android needed. The
        permission-request half already existed
        (`NotificationService.requestPermission`/`isPermissionGranted` both
        had iOS branches). The foreground-presentation half didn't:
        `DarwinNotificationDetails()` was called with no `present*` flags,
        which means iOS silently drops a local notification fired while the
        app is in the foreground — exactly the case for a rest timer someone
        is actively watching. Both call sites in `notification_service.dart`
        (`showCompletion`, `scheduleBoundary`) now pass `presentAlert:
        presentBadge: presentSound: true`.
  - [x] `file_picker` export/import: `UIFileSharingEnabled` and
        `LSSupportsOpeningDocumentsInPlace` if backups should be reachable in
        the Files app. Added to `Info.plist`.
- [x] **dev** — CI writes `supabase.json` from repository secrets before
      building; it is gitignored and will not exist on a runner. New step in
      the `ios` job of `ci.yaml`, reading `secrets.SUPABASE_URL` /
      `secrets.SUPABASE_ANON_KEY`. **Still needs an `acct` action**: those two
      secrets must be added in GitHub -> repo Settings -> Secrets and
      variables -> Actions before the iOS build carries real credentials —
      until then it degrades to an accounts-off build (same as the existing
      Android debug build), which is safe but not the end state.
- [x] **dev** — Add an iOS job to `.github/workflows/ci.yaml`. Runs on
      `macos-latest`, gated on the existing `verify` job passing first (macOS
      minutes are the 10x-cost resource this section already flags), and builds
      with `--no-codesign` — a compile check, not a signed distributable.
      Signing for actual TestFlight/App Store upload is separate, later work
      once the Apple Developer Program decision below is made.
      **Unverified**: there is no Mac or GitHub Actions run available from
      this environment, so this workflow has not actually executed. Watch
      the first real run on GitHub for anything Xcode-version- or
      CocoaPods-related that only surfaces on an actual macOS runner.
- [ ] **dev** — Work the launch plan's iOS device checks: audio-session ducking,
      notifications, wakelock, VoiceOver. Still needs a physical iPhone or
      simulator — not something to fake from a compile check.

---

### Roadmap Phase 5 — Cloud backup and sync

**Gate: Phase 3 said retention is healthy.**

> **Interim, shipped 2026-08-24 — do not mistake this for Phase 5.**
> `features/backup/` adds a manual **Account backup**: tap "Back up now",
> the whole database goes up as one gzipped ADR-7 envelope; sign in on a
> reinstall and "Restore from my account" brings it back. Built so testers
> can reinstall without losing data, and deliberately the smallest thing
> that achieves that.
>
> What it is **not**: no sync, no merge, no conflict rule, no background
> upload, no multi-device story. One slot per account, last write wins,
> restore replaces the device. It runs on Supabase's **free** tier — a
> year of training compresses to ~40KB, so 10 testers are nowhere near the
> 500MB limit and it costs nothing.
>
> Everything below still needs building, and this interim version should be
> deleted rather than extended when it is: a per-table sync that has to stay
> compatible with a whole-database blob is worse than one that doesn't.
> One-time server setup lives in `docs/cloud_backup_setup.sql`. ADR-8 has
> been amended to record the exception.
>
> **2026-09-19:** that SQL file also defines `delete_my_account()`, the
> security-definer function behind Settings → Account → Delete account
> (required by Apple 5.1.1(v) and Google Play). Any Phase 5 schema has to
> keep account deletion cascading through whatever it adds — a per-table
> sync that leaves rows behind after deletion would break the store rule
> and the privacy policy's promise.

This is the feature people actually pay for, and the only one with a genuine
recurring cost — which is what makes a subscription honest rather than
rent-seeking. It also resolves the tension in the Phase 0 welcome copy: today
the account has nothing real to sell.

**Amends ADR-8**, which currently states workouts "are never uploaded" and an
account "carries identity only". Update the ADR in the same change — an
architecture document that quietly stops being true is worse than none.

- [ ] **dev** — Supabase schema for workouts, programs, templates, body
      metrics.
- [ ] **dev** — Row-level security per user. Get this wrong and one user
      reads another's training log.
- [ ] **dev** — Upload path. Must not block a cold offline launch (ADR-6:
      capabilities degrade, they never throw).
- [ ] **dev** — Restore path, including onto a device that already has local
      data. The existing import/export merge/replace work in the audits below is the
      obvious precedent — reuse it rather than inventing a second set of
      rules.
- [ ] **dev** — Conflict handling. Two devices, same account, both edited
      offline. Decide the rule and write it down before coding.
- [ ] **dev** — Update the welcome screen and Settings copy, which currently
      say data is local-only. They will become the wrong kind of honest.
- [ ] **dev** — Amend ADR-8.

---

### Roadmap Phase 6 — Monetization

**Gate: Phase 5 shipped and works. Selling backup before it exists is how
refund requests start.**

Model: **freemium**, with cloud backup as the paid feature.

- **Free** — everything that exists today: logging, programs, timer, charts,
  local export. A tracker that nags mid-set gets deleted.
- **Paid** — cloud backup, multi-device sync, and optionally the deeper
  analytics.
- **Both price points** — subscription (~$3–5/month) *and* a lifetime unlock
  (~$30–40). Fitness-tracker users are notoriously subscription-averse;
  Strong and FitNotes both sell lifetime. The one-time buyers fund the early
  months when there is no recurring base.

- [ ] **dev** — In-app purchase plugin and purchase verification.
- [ ] **dev** — Restore-purchases flow that works **offline**. Non-trivial in
      a local-first app and worth designing deliberately, not discovering.
- [ ] **acct** — Subscription disclosure: price, renewal, cancellation, shown
      before purchase. Store policy, not a nicety.
- [ ] **acct** — Price in local currencies.

**Decided against: ads.** Banner revenue at this scale is a few dollars a
month, they are hostile during a workout, and they undercut the paid tier.
If ever revisited, rewarded-only ("watch an ad for this week's advanced
stats") is the one form that does not punish normal use.

---

### Reference — the numbers

Everything depends on whether "500 users" means subscribers or installs. It
is a 10× swing, and conflating the two is the most common way these
projections go wrong.

| | 500 **paying subscribers** | 500 **installs**, 3% convert |
|---|---|---|
| Subscribers | 500 | ~15 |
| Gross @ $5/mo | $2,500 | $75 |
| Play's 15% | −$375 | −$11 |
| Supabase Pro | −$25 | −$25 |
| Apple ($99/yr) | −$8 | −$8 |
| Domain, email | −$5 | −$5 |
| **Net / month** | **≈ $2,085** | **≈ $26** |

Play takes 15% on the first $1M/year, so the fee side is friendly.

**Reaching 500 subscribers needs roughly 10,000–25,000 active users** at a
2–5% conversion rate. That is the number to plan against — a 1–3 year project
with sustained effort, not a launch outcome.

What erodes even the good column:

- **Churn** — fitness apps lose 5–10% of subscribers monthly, worse after
  January. Holding 500 means replacing 25–50 every month, forever.
- **Failed payments** — another 3–5%: expired cards, insufficient funds.
- **Income tax** — Google is merchant of record in most countries and handles
  VAT, but tax on the profit is yours.

**Paid acquisition does not work at this price point.** Fitness installs run
roughly $0.50–$3. At $2/install with 3% conversion, one subscriber costs ~$67
to acquire and returns ~$4.25/month — 16 months to break even, longer than
most subscribers stay. Google will sell you App campaigns anyway. Don't.

**What Play does and does not do.** It gives you search (ASO is the highest
-return free work available), "similar apps" placement, and an algorithm that
rewards install velocity, retention and ratings — good metrics compound, bad
metrics make you invisible. It does **not** promote you. There is no free
editorial push for a new app.

**What works instead** is unglamorous: ASO, genuine differentiation, and
communities. Reddit's fitness subs move real numbers but punish anything that
smells like an ad — participate, don't market. Small YouTube and TikTok
fitness creators are cheaper and better targeted than Google Ads.

**The differentiator worth leaning on:** every competitor is cloud-first and
account-required. *Offline, private, yours — cloud backup optional* is a real
position, and it is already true of this app rather than something that needs
building.

---

### Roadmap decisions

| Decision | Owner | Blocks | Notes |
|---|---|---|---|
| Exercise asset source | dev | Phase 1, all of monetization | free-exercise-db recommended |
| GitHub Actions vs Codemagic | acct | Phase 4 | Actions is closer to hand; Codemagic is easier signing. Only matters if D1 = go |
| Sync conflict rule | dev | Phase 5 | Decide before coding |
| Subscription / lifetime / both | acct | Phase 6 | Both recommended. Planning only until a D7 number exists |

Apple Developer $99/yr (D1), Firebase Analytics or not (D2), brand primary
colour (D3) and web as a launch target (D5) are the launch plan's own
decisions — see its Decisions table above. They are not repeated here.

---

### Working notes

**Build commands.** Never plain `flutter build apk` — it silently produces a
binary with accounts disabled. Use `scripts/build_android.sh {apk,bundle,
install,run}`, or the committed IDE run configs.

**Verifying a build actually carries credentials**, rather than trusting the
command line:

```
unzip -p build/app/outputs/flutter-apk/app-release.apk \
  | grep -a "supabase.co"
```

**Pre-existing test failures.** None as of 2026-09-20: `flutter test` reports
423 passed, 1 skipped (the golden review harness), 0 failed, and
`flutter analyze --fatal-infos --fatal-warnings` is clean. The 6 long-standing
failures (5 `library_page_test`, 1 `program_editor_page_test`) were fixed with
the Arabic localization work; the suite is green, so any failure is now yours.

**Local tooling.** `dart run tool/check_asset_licenses.dart` used to false-fail
on Windows (mixed path separators); fixed 2026-09-20 and verified to still
catch an orphaned image.

---

*Everything from here down to Audit 2 is the first engineering audit
(Priority 0–4, the Progress feature track, the validation checklist) —
essentially complete. Its open boxes (lifecycle/device validation, TalkBack /
VoiceOver, responsive checks, import/export manual tests, final diff review)
are scheduled in the launch plan above.*

---

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
- [ ] Add tests for malformed headers, missing fields, unknown tables, invalid rows, invalid UUIDs, and missing required tables. (Malformed headers/missing fields/unknown tables/missing required tables and dangling FKs are covered; wrong-type rows and syntactically-invalid-but-unreferenced UUIDs still need dedicated coverage.)

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

- [x] Detect repeated XLSX imports using stable reconstructed workout identity. (Content-based detection compares the historical date, exercise order, and set data; a file hash was intentionally rejected because it would miss updated/appended exports of the same log.)
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
- [ ] Verify draft restoration after process termination/app restart. (Unit-level restoration through a fresh `ProviderContainer` is covered; a real process-kill integration test remains open under Priority 4.)
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
- [ ] Run the complete test suite with coverage. Full `flutter test` passes: **423 passed, 1 skipped, 0 failed** (2026-09-20; was 397 on 2026-09-19). Coverage was measured once on 2026-09-19 (see Week 3: 70.9% on `domain/` + `data/`); a fresh `--coverage` report has not been generated since, and CI runs `flutter test --coverage` with no threshold.
- [ ] Build Android debug/release artifacts. (Debug build succeeded locally; release was not attempted because signing configuration was unavailable.)
- [x] Build Web release. (`flutter build web --release` succeeds.)
- [ ] Verify iOS build and CocoaPods integration on macOS. **External validation required:** macOS/Xcode was unavailable; the repository's iOS scaffolding and setup instructions remain in place.
- [x] Resolve or document the Web font warning involving `CupertinoIcons`. (Root cause: nothing in the app calls `CupertinoIcons.*`, but Flutter's default iOS/macOS adaptive page-transition theming references the font family internally regardless, and the app never declared the `cupertino_icons` package that ships the actual font asset. Added it as an explicit dependency — the standard `flutter create` default this project had dropped. Tree-shakes down to 1.4KB since it's genuinely unused.)
- [ ] Test whether all icon families used by the app render correctly in the browser. **External visual validation required:** the Web release build passes, but a real browser screenshot/accessibility pass remains open.

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

- [x] Use the bundled free-exercise-db media for v1 with attribution and
      license metadata. This preserves the offline-first scope while keeping
      provenance visible in the app and asset documentation.
- [x] Animated demos are out of scope for v1; no CDN/cache strategy is added.
- [x] Rule out ExerciseDB (AGPL-3.0) and Gym Visual-derived sets
      (proprietary) as sources.
- [x] Store media provenance in the exercise media/source tables. The current
      schema includes `license`, `attribution`, and `source`; extend those
      fields when another licensed source is introduced.
- [x] Show attribution for bundled third-party media. The Settings/About surface
      and `LicenseRegistry` entry document the current free-exercise-db assets.

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
- [x] `flutter test` (**re-run 2026-09-20: 423 passed, 1 skipped, 0 failed.** Earlier: green as of 2026-08-26 with 337 passed, 1 skipped, 0 failed. The 6 long-standing Library/program-editor widget failures and the migration fixture failure are all fixed. Not re-run with `--coverage`; no coverage threshold is enforced anywhere.)
- [x] `flutter build apk --debug` (passes.)
- [x] `flutter build web --release` (passes.)
- [ ] iOS build verified on macOS. **External validation required:** macOS/Xcode is unavailable (no Mac; the CI `ios` job has never run). *(Un-ticked 2026-09-20: this box was checked although the note beside it says the build was never verified. Same item as Priority 2's "Verify iOS build and CocoaPods integration".)*
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
- [x] `android/app/build.gradle.kts` release block sets no `isMinifyEnabled` /
      `isShrinkResources`. **Enabled 2026-09-19** (see Week 2) with
      `proguard-rules.pro` and `res/raw/keep.xml`; a shrunk release APK boots
      on the emulator. Still needs a real device and a notification firing
      before this is trusted. **CI (2026-09-20):** the uncommitted
      `.github/workflows/ci.yaml` now builds the shrunk, obfuscated release
      APK (`flutter build apk --release --obfuscate --split-debug-info=…`),
      debug-signed — it proves the variant compiles and shrinks, not that it
      runs. The "CI does not build this variant" comment in
      `android/app/build.gradle.kts` was updated to match (2026-09-20).
      Original reasoning kept below for the record.
      *Previously:* Not a vulnerability, but it costs APK size and free
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
      reports). **Half done 2026-09-19:** the flags are in
      `scripts/build_android.sh` (symbols → `build/symbols/<version>`); *where to
      archive them* is still undecided and depends on D2. Previously left open
      for the same reason — meaningful only once a real
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

- [ ] Current `docs/ADR.md` and Roadmap Phase 5 sync design — does the temporary
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
