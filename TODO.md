# Ironyx — TODO (two-day finish)

Replanned 2026-09-20. The full 12-week plan, the post-launch roadmap and both
engineering audits are unchanged in [`docs/archive/TODO-full-plan.md`](docs/archive/TODO-full-plan.md).
Older references in code and docs ("TODO.md A2.14", "Roadmap Phase 5", "C6",
"D1", "Week 2") point into that file.

Owner tags: **me** = you, the account holder (consoles, passwords, devices);
**dev** = code or file changes Claude can do in this repo.

## Where the app really stands

Checked today, not copied from old notes:

- `flutter analyze --fatal-infos --fatal-warnings`: **no issues**.
- `flutter test`: **438 passed, 1 skipped, 0 failed** (the README's 423 was stale).
- `targetSdk` resolves to **36** with the installed Flutter 3.47.5, which meets
  Google Play's Aug 31 2026 requirement for new apps.
- The app is feature-complete. What is missing is **release plumbing**, one
  timer gap, and an untested accounts backend. Nothing else in the old plan
  blocks a first release.
- Not on this machine: `supabase.json`, `android/key.properties`, the upload
  keystore. **Update 2026-09-20:** the app was originally built on a Linux
  server, and these files are gitignored, so they were never pushed and may
  still be there. The earlier note that the original key is lost only meant
  it is missing from this Windows machine; look on the server before
  generating anything new. (A new key is still safe if it is truly gone:
  nothing was ever uploaded to Play.)
- No physical device is attached; the only Android target is the `atco_test`
  emulator. Everything timer- and notification-related has been seen on an
  emulator only.

## The one constraint code cannot remove

A personal Play developer account created after 13 Nov 2023 must run a
**closed test with at least 12 testers opted in for 14 continuous days**
before it may apply for production access
([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465)).
Organisation accounts and older personal accounts are exempt.

So "finished in two days" means: **signed build, listing, policy pages and
the closed test all live by the end of Day 2.** Public availability is then
14 days plus Google's review away. If Day 2 ends with 12 testers opted in on
Tue Sep 22, the earliest production application is Tue Oct 6.

- [ ] **me** First thing: open Play Console and note the account type and its
      creation date. If it is an organisation account, or a personal account
      from before 13 Nov 2023, the 14-day wait does not apply and this plan
      ends in a production release after Day 2 plus review.

## Decisions (defaults apply unless you say otherwise)

| # | Decision | Default | Why |
|---|---|---|---|
| D1 | iOS | **Not in v1** | No Mac, no $99 enrolment, CI iOS job never run |
| D2 | Telemetry / crash SDK | **None** | Privacy policy and listing already say "none"; Play Console *Android vitals* gives crash rates |
| D5 | Web | **Not a launch target** | Persistence never verified |
| D6 | Accounts at launch | **Keep them**, gated on the Day 1 end-to-end test (C4) | Fallback below |
| D7 | `USE_EXACT_ALARM` | **Keep** | Timer apps are an accepted use; if Play rejects it, delete the two manifest lines and alerts become inexact |

**D6 fallback.** If C4 is not passing by end of Day 1, ship v1.0 without accounts:
the release build hides Account, Backup and the welcome sign-in buttons, and
they return in 1.1. That is a scope cut and an ADR-8 change, so it needs your
approval before I touch code.

## Day 1 — make the build shippable

Lead-time items first; they cost calendar time, not effort.

- [ ] **me** **A0** On the Linux server, in the Ironyx checkout: run
      `git status` and `git log origin/main..HEAD --oneline`. Anything listed
      is work that GitHub (and therefore this machine) does not have; push it
      or tell me before we build on this checkout. Then copy the three
      gitignored things across, from a PowerShell in `F:\Ironyx` (not
      `F:\...` as the target: `scp` reads the drive letter as a host name):
      `scp USER@SERVER:~/Ironyx/supabase.json .` and
      `scp USER@SERVER:~/Ironyx/android/upload-keystore.jks android/` and
      `scp USER@SERVER:~/Ironyx/android/key.properties android/`
      (adjust the remote path). These carry passwords, so copy them with `scp`
      rather than pasting them into a chat. If the keystore is found, A3 is
      unnecessary; just back it up.
- [ ] **me** **A1** Create the Play developer account ($25) and start identity
      verification. This can take days. Everything in Day 2 that uses the
      Console waits on it.
- [ ] **me** **A2** Line up **15+ testers** with Gmail addresses (12 must stay
      opted in for 14 days; 3+ spare for drop-outs). Ask today so they can opt
      in on Day 2.
- [ ] **me + dev** **A3** Only if A0 did not find the original keystore:
      generate a new upload key: `keytool` from
      `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin` (not on PATH),
      recipe in `SETUP.md` §5. You choose the passwords; they stay in the
      gitignored `android/key.properties`. **Back up `upload-keystore.jks` and
      `key.properties` to two places the moment they exist.** Losing the key
      means never updating the listing.

Code and configuration:

- [x] **dev** **C1** Timer end notification (done 2026-09-20, uncommitted).
      `_rescheduleBoundaries` scheduled only phase *starts*, so a locked phone
      went silent when the final interval ended. It now also schedules a
      "Timer complete" notification for the total end through a new
      `NotificationService.scheduleCompletion` (own id, the existing
      `timer_complete` channel), with English and Arabic strings. It is
      rescheduled on resume and skip, cancelled by `cancelAll` on pause and
      finish, and skipped without notification permission. Five new tests in
      `test/unit/timer_controller_test.dart`; four fail against the old
      controller. Analyze clean. **Still emulator/device-unverified:** the
      alarm actually firing while backgrounded is part of C6.
- [ ] **dev + me** **C2** Host the privacy policy and a delete-account page.
      **dev, done 2026-09-20 (uncommitted):** `docs/_config.yml` (theme, and
      hides the internal docs), `docs/index.md`, `docs/delete-account.md`, and
      front matter on `docs/PRIVACY_POLICY.md`. **me, still to do, after the
      commit is pushed:** repo Settings → Pages → Deploy from branch → `main`
      → `/docs`. URLs then become `https://soshe90.github.io/Ironyx/privacy/`
      and `https://soshe90.github.io/Ironyx/delete-account/`. Open both in a
      browser before pasting them into Play Console; I could not render Jekyll
      locally, so the first load is the real test.
- [ ] **me** **C3** Supabase project, all four:
      1. Confirm the `backups` table and `delete_my_account()` exist (run
         `docs/cloud_backup_setup.sql` if unsure).
      2. Authentication → URL Configuration: add `com.soshe90.ironyx://login-callback`
         to Redirect URLs and move Site URL off `http://localhost:3000`.
      3. **Custom SMTP.** Supabase's built-in sender only delivers to your own
         team members and is capped at about 2 emails an hour, so sign-up and
         reset emails would never reach a tester. Fastest free route: Gmail
         with an app password (`smtp.gmail.com`, port 465, from
         `mustafa.salih15@gmail.com`; needs 2-step verification on).
         Source: [Supabase SMTP docs](https://supabase.com/docs/guides/auth/auth-smtp).
      4. Copy the project URL and anon key into `supabase.json` (see
         `supabase.example.json`; gitignored).
      *2026-09-21 checked over the API with the new `supabase.json` (valid,
      gitignored, publishable key, URL matches the project). Project is
      reachable; email sign-in on, sign-ups on, **email confirmation
      required**. `backups` exists and **RLS is on** (an anonymous write is
      refused with 42501). **Not confirmed:** `delete_my_account()` — the
      anonymous lookup says "not found", which is also what a function that
      is hidden from `anon` can look like, so re-run
      `docs/cloud_backup_setup.sql` (idempotent) and check it in C4. Custom
      SMTP and the redirect URL are dashboard settings I cannot see.*
      Note: the privacy policy currently names Supabase as the only third
      party. Gmail SMTP sends mail from your own address, so add one line about
      the email provider before submitting Data Safety.
- [ ] **dev + me** **C4** Accounts end to end on the release build (emulator is
      fine). Sign up → confirmation email arrives → tapping the link reopens the
      app signed in → Back up now → clear data → Restore → Forgot password →
      reset link → Delete account (and confirm the auth user is gone in the
      dashboard). About 1.5 h. **Decision point at 6 pm: if any step is still
      broken, invoke the D6 fallback.**
- [ ] **dev** **C5** Signed bundle. `scripts/build_android.sh bundle`, then
      `keytool -printcert -jarfile <aab>` must show the **new** key, not
      "Android Debug". Copy `build/symbols/<version>` somewhere durable (it is
      gitignored; without it that build's crashes cannot be read). Build release
      only with `supabase.json` present, or accounts are silently off.
- [ ] **me + dev** **C6** Smoke test of the *release* build. On a physical
      device if you have one, otherwise the emulator; record results here.
      - [ ] Cold start to dashboard, first launch after install (seeding 301
            exercises); note the time.
      - [ ] Log a workout, force-kill the app mid-workout, relaunch: draft
            restored.
      - [ ] Timer (Tabata): background, then lock the screen; phase alerts
            arrive on time and the **end notification arrives** (C1). Deny
            notification permission once and confirm the timer still works.
      - [ ] Export then import round trip; Delete all data then relaunch.
      - [ ] Arabic (RTL), dark mode, and 200% font scale on Dashboard and
            Active workout: no clipped digits.
      - [ ] TalkBack: 10 minutes on Active workout and Timer.

Day 1 exit: a release-signed AAB that passed C4 and C6, and testers lined up.

## Day 2 — store, upload, start the clock

- [ ] **me + dev** **S1** Screenshots: at least 6 phone screenshots via
      `adb exec-out screencap`, in the order in `docs/STORE_LISTING.md`
      (active workout, progress chart, program detail, data management,
      dashboard, library). English light and dark; an Arabic set of at least 4.
      Populate demo data first so charts have a trend.
- [ ] **dev** **S2** Feature graphic, 1024×500 (Pillow is installed): brand
      navy `#0B1628` and teal `#38D6C0`, the icon, and 2 or 3 of the
      screenshots. You approve before upload. The 512×512 icon for Play is
      `assets/branding/ironyx-icon-512-opaque.png` (the other two masters
      have transparent corners; do not upload them).
- [ ] **me** **S3** Play Console: create the app (Free, Health & Fitness) and
      fill the forms. I will write the exact answers as a table in
      `docs/STORE_LISTING.md`; the inputs are:
      - Listing text from `docs/STORE_LISTING.md`, plus the one line it
        recommends adding: *"You can delete your account and cloud backup from
        inside the app."*
      - Privacy policy URL and account-deletion URL from C2.
      - **Data Safety:** email and password (Supabase Auth); with backup, the
        training database as health and fitness data; encrypted in transit;
        deletable in-app and by request; nothing sold or shared for ads.
      - Health apps declaration; IARC questionnaire; target audience "not
        directed at children under 13"; ads: none; app access: no login
        required.
      - **Exact alarm declaration:** core function is the interval/rest timer
        firing phase-change alerts while the app is backgrounded.
- [ ] **me** **S4** Upload the signed AAB to a **Closed testing** track, add
      the tester list, roll out, and send the opt-in link. Testers must opt in
      *and* install; the 14-day clock needs 12 of them staying opted in.
- [ ] **dev** **S5** Docs: update `README.md` (status, 438 tests, pointer to
      this file), `docs/STORE_LISTING.md` status line, and commit.

Day 2 exit: build in closed testing, 12+ testers invited, policy pages live.

## After Day 2 — waiting time, not work

- **Days 1–14 of the closed test:** keep 12+ testers opted in; read Play
  Console → Android vitals and tester feedback; fix real bugs and upload
  1.0.x to the same track (versionCode must increase).
- **About Oct 6:** apply for production access; Play asks about the testing
  you did, so answer with real feedback.
- **Then:** Google's first-release review (can take several days). Only after
  it is live: announce it, following each community's self-promotion rules.

## Deliberately not in this plan

Each of these was in the archived plan. None is needed for a first release,
and none should be started before the closed test finishes:

iOS and TestFlight, web build QA, Sentry or any analytics, landing website and
newsletter, Product Hunt and Reddit launches, blog posts, golden-image
refresh, coverage targets, performance profiling beyond the C6 stopwatch check,
the 12-week time-tracking table, per-table cloud sync, premium and in-app
purchases, the `WorkoutXlsxImportService` per-row duplicate query, the
unreproduced A2.14 delete-all race, and the "remove local data on sign-out"
question.

## Risks

| Risk | If it happens |
|---|---|
| Play account verification is slow | Day 2's Console steps slip; nothing before them does. Start A1 first |
| Gmail SMTP blocked or unreliable | D6 fallback: ship without accounts |
| Play rejects `USE_EXACT_ALARM` | Delete the two manifest lines; alerts arrive up to about 14 s late |
| No physical device | Timers and notifications stay emulator-verified only; treat the closed test as the real-device test and watch it closely |
| Upload key lost or not backed up | Listing can never be updated; do A3's backups immediately |
