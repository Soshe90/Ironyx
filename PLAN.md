# Ironyx Plan — Release, Platforms, and Revenue

The path from "works on my phone" to "published, and possibly earning". Each
phase has a **gate**: a question to answer before the next phase is worth
starting. The gates matter more than the checkboxes — most of the ways this
goes wrong involve building Phase 5 before Phase 3 has said whether anyone
comes back.

Related documents, which this one does not duplicate:

- `TODO.md` — engineering hardening (imports, data integrity, accessibility,
  device validation). Still the source of truth for code quality work.
- `docs/ADR.md` — architecture decisions. Several items below **amend** an
  ADR; those are called out, because changing one quietly is how a codebase
  stops matching its own documentation.
- `docs/v2-ideas.md` — features deliberately deferred.

Owner column: **dev** = code, **acct** = something only the account holder can
do (dashboards, payments, legal). The `acct` items are the ones that silently
block everything else.

---

## Status — 2026-09-20

Published: no. Platforms: Android only (iOS builds are unverified — no Mac).
Revenue: none. Users: 1. `flutter analyze` clean; `flutter test` 423 passed,
1 skipped, 0 failed.

**The active tracker is now `TODO.md`'s "Launch plan — 12 weeks"** (Sep 28 –
Dec 20; Android store go-live Tue Nov 17). It schedules most of the `acct`
and `dev` items below and adds four blockers this file did not have:
in-app account deletion (done in code), the Play closed-testing gate, the
telemetry-vs-privacy-policy contradiction, and iOS not being on a launchable
path. Where the two disagree, `TODO.md` wins. Decisions taken since the
entries below (all in `TODO.md`): brand primary is **teal** (D3), web is
**not a launch target** (D5), success floors accepted (D4); D1 (iOS) and D2
(telemetry) are still open.

Things this file used to say that have since changed: the catalogue is now
**301 exercises / 602 images** (seed v17), still all public domain; the
privacy policy is written (`docs/PRIVACY_POLICY.md`) but **not hosted**;
release shrinking and obfuscation are on; the account holder has decided to
declare `USE_EXACT_ALARM` for timer alerts (Play may reject it); and the
release keystore described in Phase 2 is **not present on the current
Windows machine** — locate it or generate a new upload key before the first
Play upload.

---

## Status history

### 2026-08-24

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

### 2026-09-15

App renamed **FitTrack → Ironyx**. Cause: a Play Store check found
"FitTrack" already used by 5+ published apps, one with near-identical
positioning — a solo dev with no ad budget can't win ASO against exact-name
duplicates. Checked "Ironyx" has no existing Play Store listing *(Play only —
the App Store name, a trademark search and the domain are still open;
`TODO.md` C13)*. Changed: Android manifest label, iOS `CFBundleDisplayName`,
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

## Phase 0 — Done 2026-08-23

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

## Phase 1 — Blockers before publishing

**Gate: is every asset in the APK legally ours to ship commercially?**

### Exercise catalogue licensing — done 2026-08-24

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

### Legal and store requirements

- [ ] **acct** — Privacy policy, publicly hosted. Mandatory for Play
      regardless of monetization. Must cover Supabase (email + auth) and
      anything added in Phase 2. *(2026-09-20: **written** —
      `docs/PRIVACY_POLICY.md`, last updated 2026-09-20 — covers Supabase,
      cloud backup, in-app account deletion and the permission list. **Not
      hosted anywhere**, so this box stays open; hosting is `TODO.md`
      Week 2. It must be revised in the same change as any telemetry
      decision, D2.)*
- [ ] **acct** — Play Data Safety form.
- [ ] **acct** — Play health-apps declaration. Fitness data is a sensitive
      category with its own disclosure requirements.
- [ ] **acct** — Confirm Play supports merchant payouts in your country
      *before* building anything in Phase 6. This is a hard stop, not an
      inconvenience, and it is cheap to check now.

### Technical tidy-up

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
      entry above still needs the matching update (`TODO.md` Week 2).
- [x] **dev** — Fix the 6 pre-existing test failures (5 in
      `library_page_test.dart`, 1 in `program_editor_page_test.dart`). Fixed
      during the Arabic localization work; `flutter test` now reports 337
      passed, 1 skipped, 0 failed (verified 2026-08-26).
- [ ] **dev** — Real-device validation from `TODO.md` Priority 2: force-kill
      recovery, timer across backgrounding, wakelock release, notification
      rescheduling.

---

## Phase 2 — Publish free on Play

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
      the old one, and back it up at creation (`SETUP.md` §5). Until then a
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
      Console covers the basics. *(2026-09-20: superseded by `TODO.md`
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

## Phase 3 — Learn retention — **the gate that matters**

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

## Phase 4 — iOS

**Gate: is $99/year worth it before there is any revenue?** Nothing here
requires owning a Mac; only the compile does, and that can be rented by the
minute.

> **2026-09-20 — scheduling.** `TODO.md` makes this an explicit go/no-go
> (D1, Mon Oct 5) with **Android-first, iOS fast-follow in Q1 2027** as the
> default. iOS icon and launch images were replaced 2026-09-19 (opaque
> RGB icons, navy launch storyboard) but never seen in Xcode. Two caveats
> for whoever picks this up: timer sound cues currently use
> `SystemSound.play`, which docs say gives nothing useful on iOS (no cue
> files are bundled — ADR-4 deviation note), and the iOS iCloud/iTunes
> backup-exclusion item (`TODO.md` A2.3) is still open.

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
      minutes are the 10x-cost resource this file already flags), and builds
      with `--no-codesign` — a compile check, not a signed distributable.
      Signing for actual TestFlight/App Store upload is separate, later work
      once the Apple Developer Program decision below is made.
      **Unverified**: there is no Mac or GitHub Actions run available from
      this environment, so this workflow has not actually executed. Watch
      the first real run on GitHub for anything Xcode-version- or
      CocoaPods-related that only surfaces on an actual macOS runner.
- [ ] **dev** — Work `TODO.md`'s iOS device checks: audio-session ducking,
      notifications, wakelock, VoiceOver. Still needs a physical iPhone or
      simulator — not something to fake from a compile check.

---

## Phase 5 — Cloud backup and sync

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
      data. The existing import/export merge/replace work in `TODO.md` is the
      obvious precedent — reuse it rather than inventing a second set of
      rules.
- [ ] **dev** — Conflict handling. Two devices, same account, both edited
      offline. Decide the rule and write it down before coding.
- [ ] **dev** — Update the welcome screen and Settings copy, which currently
      say data is local-only. They will become the wrong kind of honest.
- [ ] **dev** — Amend ADR-8.

---

## Phase 6 — Monetization

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

## Reference — the numbers

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

## Open decisions

| Decision | Owner | Blocks | Notes |
|---|---|---|---|
| Exercise asset source | dev | Phase 1, all of monetization | free-exercise-db recommended |
| Apple Developer $99/yr | acct | Phase 4 | No free path onto a real iPhone. **= `TODO.md` D1, due Mon Oct 5**; default is Android-first |
| GitHub Actions vs Codemagic | acct | Phase 4 | Actions is closer to hand; Codemagic is easier signing. Only matters if D1 = go |
| Firebase Analytics or not | dev | Phase 2 | **= `TODO.md` D2, due Fri Oct 2**; recommendation is Sentry only, no analytics SDK |
| Sync conflict rule | dev | Phase 5 | Decide before coding |
| Subscription / lifetime / both | acct | Phase 6 | Both recommended. Planning only until a D7 number exists |
| Brand primary colour | dev | store assets | **Decided 2026-09-19 (D3): teal.** Theme seed now matches the icon |
| Web as a launch target | dev | — | **Decided 2026-09-19 (D5): no.** Post-launch demo at most |

---

## Working notes

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

**Local tooling caveat.** `dart run tool/check_asset_licenses.dart` false-fails
on Windows (mixed path separators); trust the Linux CI run. See `SETUP.md`.
