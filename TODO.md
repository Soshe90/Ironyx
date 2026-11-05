# Ironyx — TODO (two-day finish)

Replanned 2026-09-20. The full 12-week plan, the post-launch roadmap and both
engineering audits are unchanged in [`docs/archive/TODO-full-plan.md`](docs/archive/TODO-full-plan.md).
Older references in code and docs ("TODO.md A2.14", "Roadmap Phase 5", "C6",
"D1", "Week 2") point into that file.

Owner tags: **me** = you, the account holder (consoles, passwords, devices);
**dev** = code or file changes Claude can do in this repo.

## Where the app really stands

**Update 2026-11-03 (after the drive failure).** This section below is from
2026-09-20; these are the current facts:

- The original drive failed. Work from Oct 5 to 22 that had never been pushed was rebuilt from
  recovered files as commit `a27f910` on `recovery/2026-10-22`. The audit
  record is `RECOVERY_MERGE_MANIFEST.json`.
- **1.0.3 (versionCode 4) is on a Play track.** The owner's SM N970F installed
  it from Play on 2026-10-24. Its signer `5D:8A:EA:72…` is Google's
  app-signing key, which explains the C6 "different signer" note: Play
  re-signs uploads. A locally signed APK therefore cannot update that
  install; test release builds through a Play testing track. The next upload
  needs versionCode ≥ 5.
- **The reconstruction was verified against that Play build.** Rebuilt from the
  same `F:\Ironyx` path, the Dart machine code is byte-identical, the strings,
  614 bundled assets and the app's own Android resources match, and Library and Timer
  screens are pixel-identical side by side. The Dart data snapshot differs
  by a few bytes in what looks like ordering. That is not fully explained, and the visual check
  found no visible difference.
- Upload keystore and `key.properties`: backed up to the owner's Google Drive
  (owner-reported 2026-11-03).
- `flutter test`: **876 passed, 1 skipped, 0 failed** (2026-11-05).
- Fixed 2026-11-05: a debug build sometimes showed a full-screen
  `'_dependents.isEmpty': is not true` after pressing Save in a set's "RPE
  and rest time" dialog. The dialog disposed its text controllers while it
  was still animating closed. The body-measurement dialog on Progress had
  the same fault. Each dialog now owns its controllers. Release builds strip
  the assertion, so the Play build never showed the screen. **Not checked on
  a phone.**
- Fixed 2026-11-05, same dialog: an RPE or rest time could not be removed
  once entered, and an out-of-range value made Save do nothing without
  saying why.
- Changed 2026-11-05: the debug error screen now names the first error of a
  burst, the widget blamed and the top stack frames, and the release one is
  translated (`UncaughtErrorView`, `ErrorBurst` in `core/error_reporting.dart`).
- Fixed 2026-11-05: the body-measurement dialog closed and saved nothing,
  without a message, when the weight was empty, zero or not a number, and
  it accepted any positive weight and any body-fat value. It now stays open
  and says what it accepts: 25 to 350 kg (the limits Personal details
  already used, now shared in `core/body_limits.dart`) and 2 to 70 % body
  fat. Rows already stored outside those limits are left alone.
- Fixed 2026-11-05: a measurement's day is stored as UTC midnight and was
  read back as local time, which west of UTC is the evening before.
  Reproduced with `TZ=PST8PDT flutter test`: the entry showed the previous
  day, saving an edit overwrote the previous day's entry, deleting removed
  it, and five edits moved the date back five days. `BodyMetrics.fromDrift`
  now carries the stored day as a local date. East of UTC, which includes
  the owner's phone, none of this was visible. Rows already damaged by an
  edit west of UTC cannot be told apart from correct ones and are not
  repaired.
- Fixed 2026-11-05: Personal details logged the weight under the UTC date,
  so a weight saved between midnight and 03:00 in Baghdad went to
  yesterday. It uses the local day now.
- CI runs the calendar-day and week test files in three more time zones
  (2026-11-05; the step passes). Locally, on Windows, the equivalent is
  `TZ=PST8PDT flutter test` (three-letter zone names only). That gives a
  fixed offset: Windows cannot simulate a zone that changes its clocks, so
  the clock-change tests are only meaningful on CI.
- Added 2026-11-05: **Settings → Week starts on** (Saturday, Sunday or
  Monday; Monday until chosen, so nothing regroups on update). It feeds the
  weekly totals and streaks, the dashboard week card and day strip, the
  history calendar and the Progress weekday chart, through one value
  (`WeekStart`, `weekStartControllerProvider`). Stored on the device like
  the weight unit: not in exports or cloud backups, so a restore on a new
  phone starts at Monday. Nothing is stored by week, so switching only
  regroups what is shown.
- Changed 2026-11-05, with it: weekly totals, streaks and the Progress
  weekday chart were grouped by UTC weeks and days while the dashboard used
  the phone's time. At UTC+3 a workout between midnight and 03:00 on a
  week's first day was counted in the week before. They all use the
  phone's time now, so some past workouts near a week boundary moved to the
  neighbouring week on the charts. The offset is one constant per query: a
  workout within an hour of midnight on a week's first day, in a season
  with the other clock setting, can still land a day off.
- Fixed 2026-11-05: "last week" and the weekly streak stepped
  back 168 hours, which lands on 23:00 the day before across a clock
  change, so the streak broke for that week. They step by calendar week
  now. Iraq has no clock changes, so the owner's phone never showed it.
  The tests for it pass on CI under America/Los_Angeles and
  Pacific/Auckland, which change their clocks. The old code was reasoned to
  fail there, not run there.
- Fixed 2026-11-05: number fields dropped a decimal comma as it was typed,
  so "82,5" in a set row was logged as 825 kg, and dropped Arabic-Indic
  digits entirely. Every number field (set rows, RPE and rest, body
  measurement, Personal details, timer, a program's target sets) now goes
  through `NumberInputFormatter` in `core/formatters/number_input.dart`,
  which reads `,`, `٫` and `،` as a decimal point and Arabic-Indic and
  Persian digits as 0–9. A comma is never a thousands separator. **Not
  checked:** what the owner's Samsung keyboard actually sends in Arabic.
  Not changed: the XLSX importer still reads text cells with
  `double.tryParse`, so a cell holding the text "82,5" is skipped.
  **Checked on the SM N970F, 2026-11-05:** in English (en-GB) Samsung's
  number keyboard shows a comma key that sends nothing in these fields
  (Android's decimal input type accepts only "."); the dot key works.
- Changed 2026-11-05, seed 17 → 18 (304 exercises): the Intermediate 3-,
  4- and 5-day programme workbooks name 40 exercises. 37 were already in
  the catalogue under other names and are now aliases of them; 3 were
  missing from free-exercise-db and were written for the app (Behind-the-
  Body Cable Curl, Lean-In Lateral Raise, Banded Hip Abduction: no images,
  source `ironyx` in ASSETS-LICENSE.md). Both importers now match names and
  aliases (`ExerciseDao.exerciseIdsByLookupName`); the workout importer's
  private name list is gone, and three of its matches were wrong (low-
  incline press to the flat press, chest-supported machine row to the
  cable row, leg-press calf raise to the standing calf raise). Before this,
  importing those workbooks created 19 bare custom duplicates. Upgrade from
  seed 17 checked on the phone (debug build): 304 exercises, data kept.
- Closed 2026-11-05: the owner confirmed those workbooks were never
  imported into the Play app (they were a reference for which exercises to
  add), so no custom duplicates exist to merge.
- Done 2026-11-05, seed 23: pictures for the three exercises written for
  the app, from images the owner generated (two with ChatGPT, the lateral
  raise with Google Gemini). Originals, checksums and what is unverified
  about the tools' terms are in ASSETS-LICENSE.md;
  `scripts/prepare_owner_images.py` makes the bundled frames. The Lean-In
  Lateral Raise's steps now lean away from the post, as its picture does
  (owner's decision). The exercise sheet shows every picture of an exercise
  (start and end), swiped between. **Open:** the owner has to read the
  ChatGPT and Gemini terms before a release ships the images.
- Changed 2026-11-05, Progress tab (uncommitted at the time of writing):
  - **Wrong data fixed.** Effort, rest, session volume and weekly-by-muscle
    were tables that printed the first 8 or 12 rows of an oldest-first
    query, so a three-month view showed the sessions from three months ago
    and never the newest. They are charts over every session now. The
    smoothed lines no longer dip below real values
    (`preventCurveOverShooting`), a series of equal values is drawn
    mid-chart instead of on the bottom edge, and axis dates no longer
    overprint in Arabic. Muscle-group names and the insight's exercise name
    are translated.
  - **Layout.** The range and four chapter tabs (Strength, Volume, Habits,
    Body) are pinned above the scroll view; a tab scrolls to its chapter and
    follows the reader. Est. 1RM and session volume share one card with a
    switch, as do effort and rest; tapping a muscle group shows its weeks.
    New shared control: `SegmentedPills` (docs/widgets.md).
  - No query, provider or schema changed. Review pictures of the whole
    page: `flutter test test/golden/progress_review_golden_test.dart
    --update-goldens --run-skipped`, output in `build/progress_review/`.
  - **Not done:** a per-session value is now reachable by touch (tooltip)
    and summarised for screen readers (latest, lowest, highest), but is no
    longer listed row by row. Weekly bar charts still have no value axis.
- **Open, owner's question 2026-11-05:** "EZ bar wide-grip upright row" is
  not in the catalogue (only the narrow-grip Upright Row). The programme
  workbooks list "Wide Grip BB Upright Row (last resort)" as an
  alternative. Proposed and not started: add "Wide-Grip Upright Row" as a
  fourth exercise written for the app.
- **Open, found 2026-11-05:** in Arabic, the Library list shows equipment
  in English ("Bodyweight", "Machine") in each row's subtitle; the detail
  sheet translates it.
- Fixed 2026-11-03: the dashboard greeting, date and week windows went stale
  while the app stayed in memory (seen on the phone as "Good evening, Friday
  30 Oct" on Tuesday 3 Nov morning). They now follow `localNowProvider` /
  `todayProvider` in `core/services/clock.dart`. The Tracker calendar's
  visible month, "today" ring and history-row highlight had the same
  pattern and use the same providers now. **Not audited:** other
  `DateTime.now()` reads in Progress and body-metric widgets.

Checked 2026-09-20, not copied from old notes:

- `flutter analyze --fatal-infos --fatal-warnings`: **no issues**.
- `flutter test`: **438 passed, 1 skipped, 0 failed** (the README's 423 was stale).
- `targetSdk` resolves to **36** with the installed Flutter 3.47.5, which meets
  Google Play's Aug 31 2026 requirement for new apps.
- The app is feature-complete. What is missing is **release plumbing**, one
  timer gap, and an untested accounts backend. Nothing else in the old plan
  blocks a first release.
- `supabase.json`, `android/key.properties` and the upload keystore were
  missing on 2026-09-20 (the app was originally built on a Linux server and
  these files are gitignored). **Update 2026-09-21:** all three are now on
  this machine. The keystore is the original key (alias `fittrack_upload`,
  created 2026-08-26); the properties file arrived as `key.properties.txt`
  and was renamed, because Gradle reads only `key.properties`.
- No physical device is attached. **Update 2026-09-21:** the `atco_test`
  emulator cannot boot on this machine either: its AVD definition exists but
  the Android 35 `google_apis` x86_64 system image is not installed, and
  there are no `cmdline-tools` to install one. C6 and S1 need either that
  SDK download (about 1.5 GB) or a physical Android phone over USB.
  Everything timer- and notification-related has so far been seen on an
  emulator on another machine only.

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
      *2026-09-21: `supabase.json`, the keystore and `key.properties` are
      here (the properties file needed renaming from `.txt`). Still open:
      the `git status` / `git log origin/main..HEAD` check on the server, and
      backing up the keystore and `key.properties` to two places.*
- [ ] **me** **A1** Create the Play developer account ($25) and start identity
      verification. This can take days. Everything in Day 2 that uses the
      Console waits on it.
- [ ] **me** **A2** Line up **15+ testers** with Gmail addresses (12 must stay
      opted in for 14 days; 3+ spare for drop-outs). Ask today so they can opt
      in on Day 2.
- [x] **me + dev** **A3** *Not needed: A0 found the original keystore
      (2026-09-21).* Only if A0 did not find the original keystore:
      generate a new upload key: `keytool` from
      `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin` (not on PATH),
      recipe in `SETUP.md` §5. You choose the passwords; they stay in the
      gitignored `android/key.properties`. **Back up `upload-keystore.jks` and
      `key.properties` to two places the moment they exist.** Losing the key
      means never updating the listing.

Code and configuration:

- [x] **dev** **C1** Timer end notification (done 2026-09-20, commit `c9ae406`).
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
      **dev, done 2026-09-20 (commit `d3f36a9`):** `docs/_config.yml` (theme, and
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
      Note: the privacy policy named Supabase as the only third party, and
      whichever SMTP provider you pick sends the emails. **dev, done
      2026-09-21:** `docs/PRIVACY_POLICY.md` now says sign-up and reset emails
      go through an email-sending service acting on our behalf (provider-neutral,
      so it stays true for Gmail or any other SMTP); "Last updated" is
      September 21, 2026.
- [ ] **dev + me** **C4** Accounts end to end on the release build (emulator is
      fine). Sign up → confirmation email arrives → tapping the link reopens the
      app signed in → Back up now → clear data → Restore → Forgot password →
      reset link → Delete account (and confirm the auth user is gone in the
      dashboard). About 1.5 h. **Decision point at 6 pm: if any step is still
      broken, invoke the D6 fallback.**
      *2026-09-21 split:* the **server half** needs no device and can be run
      by API once C3 is done: sign up a test address, confirm it by clicking
      the mailed link (the account confirms on Supabase's side even though the
      browser cannot open the `com.soshe90.ironyx://` redirect), sign in, write
      and read a backup as that user, call `delete_my_account`, then confirm
      sign-in fails and the `backups` row is gone. That proves SMTP, RLS and
      the delete function. The **app half** (link reopens the app signed in,
      Restore after clearing data, the reset-password screen) still needs a
      device. Code review of `SupabaseAuthService` and the deep-link wiring
      found no defect. Tester tip: open the confirmation link on the phone
      that has the app installed, or it cannot hand back to the app.
      Verification query for the delete function, to run after the SQL:
      `select prosecdef, has_function_privilege('authenticated','public.delete_my_account()','execute') as auth_can, has_function_privilege('anon','public.delete_my_account()','execute') as anon_can from pg_proc where proname = 'delete_my_account';`
      Expect `true / true / false`.
- [x] **dev** **C5** Signed bundle. `scripts/build_android.sh bundle`, then
      `keytool -printcert -jarfile <aab>` must show the upload key, not
      "Android Debug". Copy `build/symbols/<version>` somewhere durable (it is
      gitignored; without it that build's crashes cannot be read). Build release
      only with `supabase.json` present, or accounts are silently off.
      *Done 2026-09-21:* `build/app/outputs/bundle/release/app-release.aab`
      (87.7 MB, 1.0.0+1) is signed with the upload key (SHA-256
      `57:08:11:C8:EC:BF:DD:43:D2:0B:FA:FA:63:B0:80:62:5C:9A:57:05:2B:55:07:B3:C3:3A:BE:79:D7:F7:7D:90`,
      matching `fittrack_upload`). On this machine the build needs
      `scripts/build_android.sh bundle -P kotlin.incremental=false`, because
      the pub cache is on `C:` and the repo on `F:` (SETUP.md §6). The
      release APK from the same flags has the Supabase host compiled in, so
      accounts are on. **Still to do (me):** copy `build/symbols/1.0.0+1` and
      the keystore + `key.properties` to durable storage.
- [ ] **me + dev** **C6** Smoke test of the *release* build. On a physical
      device if you have one, otherwise the emulator; record results here.
      **Blocked 2026-09-21:** no working Android target on this machine (see
      "Where the app really stands"). The release APK is built at
      `build/app/outputs/flutter-apk/app-release.apk`; plug in a phone with
      USB debugging on, or approve the emulator image download, and the rest
      is `adb install` plus the checks below.
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
      *2026-09-29, automated on the LMR LX9 (Android 12) over USB with
      `scripts/run_device_tests.sh` (debug build, 26 journeys in
      `integration_test/`, all passing). Covered: first launch seeds 301
      exercises in ~4.5–4.9 s; draft survives a simulated kill; timer
      alarms really queued with Android (3 boundaries + completion) and
      cleared on pause/end; 400 workouts / 6,400 sets export in ~0.4 s
      (4 MB) and import in ~2 s; Arabic, 200 % text and dark mode lay out
      without overflow. **Found and fixed:** the timer never finished on a
      real device (just_audio's `play()` never completes at a clip's end, so
      the screen stayed open and the session was never saved), and the
      Delete-all dialog overflowed with the keyboard up. Both are in the
      working tree, **not** in the 25 Sep release APK. Still manual: the
      *release* build, a real force-kill, locked-screen alert timing,
      denied notification permission, TalkBack.*
      **Warning:** on 2026-09-29 an on-device test run uninstalled the
      release app and its data. Debug builds now use
      `com.soshe90.ironyx.debug`; run device tests only through the script,
      which refuses while the release app is installed.
      *2026-10-22: the SM N970F (Android 12) ran the debug-build workout
      journey: 9/9 passed, including immediate Finish after typing reps and
      two rapid Finish taps. The discard journey's old assertion was updated
      to the current immediate-discard/Undo behavior. This did not test the
      release build, real force-kill, locked-screen alerts, denied permission,
      export/import, Arabic layout or TalkBack; C6 stays open.*
      *2026-10-22 release-build check on SM N970F: `scripts/build_android.sh
      apk -P kotlin.incremental=false` built 1.0.2+3 with Supabase defines,
      release minification and 15 packaged native libraries confirmed stripped.
      The APK's upload-key signer SHA-256 begins `57:08:11:C8`, but the
      already-installed `com.soshe90.ironyx` 1.0.2+3 APK's signer begins
      `5D:8A:EA:72` (checked with `apksigner` after pulling its base APK).
      Android cannot update an installed app with a differently signed APK;
      uninstalling would erase local data. Nothing was installed or cleared.
      Release runtime checks remain open until a separate device/emulator is
      available, or the owner confirms a verified backup and explicitly
      authorizes a destructive reinstall. The debug integration test is not
      a substitute for release-build testing.*

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
      fill the forms. **dev, done 2026-09-21:** the exact answers are a
      form-by-form table in `docs/STORE_LISTING.md` ("Play Console answers"),
      with `(verify)` wherever it names a console label from memory; the
      "delete your account" sentence is already in the description, gated on
      C4. Target audience is recommended as **18 and over**, not "13+", to stay
      out of the Families policy; say if you want otherwise. The inputs are:
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
      *2026-09-21: README, STORE_LISTING, SETUP and the privacy policy are
      updated in the working tree. Not committed or pushed yet; the Pages
      toggle in C2 needs the push.*

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

## Product research backlog — 2026-10-22 (not part of the two-day finish)

Read-only market and repo review. **No feature below is approved for implementation.**
Finish C4/C6 and the closed test before expanding scope; use tester evidence to
choose one improvement at a time. Sources describe competitor *claims*, not
hands-on verification. US advertised prices are not verified checkout prices.
The store listing is still a draft, not proof of actual users or positioning.

### Current product and positioning

- **Verified in repo:** unpublished, Android-first offline strength-training
  log: five areas (Home, Tracker, Library, Timer, Progress); sets/reps/weights,
  reusable programs, 301 seeded exercises, progress charts, English/Arabic,
  versioned export/import and optional account/manual one-slot cloud backup.
  Local SQLite is the source of truth; backup/restore **is not sync**
  (`README.md`, `docs/ADR.md` ADR-1, 3, 7, 8).
- **Assumed audience, to validate:** adults following repeatable lifting plans
  who want fast set entry, previous-session context and reliable gym-time use
  without a network or mandatory account. No customer research establishes the
  segment size, retention, willingness to pay or reasons to switch.
- **Proposed positioning, not approved store copy:** “Ironyx is a focused
  workout log for lifters who want to follow their plan, record every set, and
  understand their progress—even without a connection. Training stays on your
  device by default, with export and optional manual backup under your
  control.” Never imply automatic protection, multi-device sync, AI coaching,
  iOS/web support at launch, or exclusive Arabic/offline capabilities.
- **Verified limitations:** C4 still needs the real account/backend journey;
  C6 still needs release-build device checks; S1 needs store screenshots.
  Account backup contains training and profile data, is manual and last-write-
  wins; restore replaces local user data. Gzip is not client-side encryption.
  Uninstalling without a file export or successful backup can lose history.
  Web persistence and iOS operation are unverified (`docs/ADR.md`, `SETUP.md`).
  CSV program import has a specified format; XLSX history import targets a
  particular workbook layout, not arbitrary competitor exports (`README.md`).

### Competitor watchlist and source notes

Checked 2026-10-22: public US store listings, official pages and displayed
reviews. Product descriptions, UI imagery and release notes are developer
claims; no competitor app was installed. Prices, offers, review selection and
features may change by region/date. **Do not claim “only offline” or “only
Arabic”: Hevy lists Arabic, and Hevy, Alpha Progression and Boostcamp advertise
some offline logging; FitNotes is already free and ad-free on Android.**

| Comparator | Relevant offering / AI evidence | Advertised US price and recent update | Evidence |
|---|---|---|---|
| Strong (direct) | Focused routines, previous workouts, timer, charts, Watch, sync; no native-AI claim established | Free unlimited workouts/3 custom routines; Pro $4.99/mo or $29.99/yr advertised (other purchase entries exist). iOS 6.5.1, Oct 8: sign-in/sync fixes | [App Store](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577) |
| Hevy (direct/social) | Sets, routines, charts, friends, desktop/watch, advertised offline; Trainer guidance has unverified generation method; **iOS lists Arabic** | Pro entries include $2.99/mo, $23.99/yr, $74.99 lifetime; another monthly entry exists. iOS 3.2.2 around Oct 21: notes update | [App Store](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350), [site](https://www.hevyapp.com/) |
| FitNotes (direct/lean Android) | Daily exercise → save sets → history, timer, routines, backup, CSV; no native-AI claim established | Core free/no ads; Play displays Oct 24, 2025 update; iOS not planned per developer | [Play](https://play.google.com/store/apps/details?id=com.github.jamesgay.fitnotes&hl=en_US&gl=US), [quick start](https://www.fitnotesapp.com/quick_start/), [FAQ](https://www.fitnotesapp.com/faq/) |
| JEFIT (broad planner) | Large exercise/program catalogue, Wear OS, charts; markets AI adaptive plans and weight/rep suggestions, quality/method unverified | Basic free; Elite $12.99/mo or $69.99/yr in US listing. Play Oct 10: Wear OS timer/timed sets | [Play](https://play.google.com/store/apps/details?id=je.fit&hl=en_US&gl=US) |
| Alpha Progression (guided) | Account-free logging/manual plans; performance-based recommendations and generated plans are Pro. Existing plans/recommendations advertised offline; new plan generation needs network. Generative-AI claim **not** established | Pro regular US $12.99/mo or $79.99/yr. iOS 7.7, Oct 6: additional CSV export routes | [site/FAQ](https://alphaprogression.com/), [App Store](https://apps.apple.com/us/app/alpha-progression-gym-tracker/id1462277793) |
| Boostcamp (program-first/indirect) | Free program library, tracker; markets questionnaire “AI coach”, Pro auto progression, offline workouts; AI method unverified. Official and store library counts disagree | Pro $59.99/yr or $14.99/mo advertised. iOS 266, Oct 2: auto progression and alternatives | [Pro](https://www.boostcamp.app/pro), [App Store](https://apps.apple.com/us/app/boostcamp-workout-tracker/id1529354455) |

**User-review signals, not prevalence or verified current defects:** a 2023
[Strong review](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577)
requested flexible exercise types; a 2024
[Hevy review](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350)
reported tedious backdated-workout entry; a 2025
[Boostcamp review](https://apps.apple.com/us/app/boostcamp-workout-tracker/id1529354455)
reported a finish-workout freeze. Boostcamp's older offline complaint has a
2024 developer reply saying offline mode was added: **do not** call offline
absence a current defect. No specific recurring FitNotes complaint was
substantiated by the displayed reviews. Review samples do not prove a market
trend. Competitor UI conclusions are limited to official descriptions/images,
not measured usability or task completion.

### Prioritized findings and validation gates

- [ ] **me + dev — launch gate (C4/C6/S1, not new scope):** verify sign-up,
      confirmation, manual backup/restore, recovery and deletion against the
      live backend; review live RLS, data access/retention and account deletion
      before strengthening privacy claims. Smoke-test the release APK on a
      physical Android device, including real kill/resume, airplane mode,
      background/locked timer, denied permission and TalkBack. Capture *real*
      populated Library, data-management, light/dark and Arabic/RTL screens.
      The `test/golden/` files are skipped review fixtures: Library is loading,
      and Settings renders Arabic as replacement glyphs; neither proves
      real-device RTL quality. Preserve the D2 no-telemetry decision unless
      explicitly reconsidered with policy/listing updates.
- [x] **dev — P0, CSV import discoverability:** the Programs heading now has
      an always-visible options menu with a labeled CSV import item; the empty
      state still offers import. Widget tests cover both states and `README.md`
      describes the actual entry point. Code and tests verified locally
      2026-10-22; a manual device usability check is still worthwhile.
- [x] **dev — P0, CSV import validation and failure handling:** preview now
      names skipped unknown exercises, existing programs and malformed rows;
      invalid set counts are not silently defaulted. Apply failure is caught
      and reported without showing raw database errors. Unit and widget tests
      cover invalid input and forced write failure; CI-equivalent checks passed
      locally 2026-10-22. This is not a general spreadsheet migration tool.
      Large historical XLSX profiling remains deferred under the launch plan.
- [ ] **me + dev — P0 discovery:** run 8–12 consent-based Android usability
      sessions, including 4+ active Arabic users and people currently using
      rival loggers; compare first workout, repeat session, kill/resume,
      offline session, backup explanation and finding import. Observe task
      time, errors, corrections and return choice; do not collect unnecessary
      health data. Proposed gates: zero lost/duplicated sets in scripted
      recovery, every participant distinguishes local save from cloud backup,
      and no critical Arabic task failure. These are *targets*, not results.
- [ ] **dev + me — P1 candidate, select only after discovery:** make the
      already auto-persisted draft and last *successful* manual backup status
      legible; show backup date and replacement impact before restore. Problem:
      fear of lost data; competitors market sync/backup. Difference: explicit
      local/file/cloud provenance, not falsely reassuring “saved” after a
      failed write. Complexity **medium**; ongoing account-support/testing
      cost; risks are stale backups, false success, multi-device overwrites.
      Prototype copy and test users' understanding plus kill/network failures.
- [ ] **dev + me — P1 candidate:** refine existing “last time → today” set
      context instead of building a coach. Hevy shows past sets; Ironyx already
      displays them in `test/golden/active_workout.png`. Test speed, errors and
      visual clutter with a small optional display. Complexity **low–medium**,
      local-query maintenance; avoid comparing warm-ups, imported anomalies or
      different exercises as equivalent.
- [ ] **dev + me — P1 candidate, separate approval:** prototype explainable,
      optional progression prompts from sufficient comparable logged sets.
      Alpha Progression/JEFIT/Boostcamp already recommend targets; distinguish
      with inspectable source sets and user control, **not** “AI”. Validate
      comprehension and demand first. Complexity **medium–high**, local
      computation but substantial rules/tests; risks: misleading fitness
      guidance, sparse history, exercise equivalence and alert fatigue. No
      automatic plan edits or health/injury claims.
- [ ] **dev + me — P1 candidate, separate approval:** prototype one permitted
      source-format import with column/exercise/unit mapping, unmatched and
      duplicate preview, atomic apply and pre-import recovery. Strong and
      Alpha Progression offer CSV export; historical entry is a user pain,
      but no broad Ironyx importer exists. Complexity/support **high**;
      malformed files, memory, large-history query cost, unit and identity
      errors. Measure completed migrations and correction effort first.
- [ ] **dev + me — P1 candidate:** conduct bilingual device usability and
      accessibility passes across the *whole workout* (search, weights/units,
      timer, recovery), then fix measured RTL, mixed-numeral, typography,
      focus-order or clipping problems. Hevy already lists Arabic; quality,
      not exclusivity, must be proven. Complexity **medium** with recurring
      translation QA; test task time and error rate in both languages.
- [ ] **dev + me — P2 candidate:** optional factual weekly progress brief
      linking to underlying workouts, with explicit insufficient-data state.
      Competitors already offer charts. Complexity **medium**; SQL/index and
      multi-year profiling needed; avoid extrapolation or punitive streaks.
      Validate whether it helps users decide what to do next.

**Table stakes to protect:** fast editable set logging, previous performance,
programs, timer, search, interpretable progress, offline draft recovery and
portable history. **Avoid until evidence/approval:** social feed, AI/LLM health
coach or sensitive-data upload, automatic per-table sync, copying competitors'
branding/media/layouts or racing their program-library counts. Sync would
change ADR-8, conflict handling, privacy and operating costs: propose it
separately and obtain approval before any design or implementation. Reuse the
existing teal theme, five-tab navigation and focused workout UI; device-test
large text, keyboard and touch targets instead of reskinning from screenshots.

**Research exit:** after closed testing, compare whether users choose Ironyx
for a calmer, trustworthy repeat workout over the alternatives. If they
mainly need guided plans or social/community, do not build a shallow imitation.
Choose one proven problem, specify measurable success and maintenance cost,
then update the live plan before coding.

## Risks

| Risk | If it happens |
|---|---|
| Play account verification is slow | Day 2's Console steps slip; nothing before them does. Start A1 first |
| Gmail SMTP blocked or unreliable | D6 fallback: ship without accounts |
| Play rejects `USE_EXACT_ALARM` | Delete the two manifest lines; alerts arrive up to about 14 s late |
| No physical device | Timers and notifications stay emulator-verified only; treat the closed test as the real-device test and watch it closely |
| Upload key lost or not backed up | Listing can never be updated; do A3's backups immediately |
