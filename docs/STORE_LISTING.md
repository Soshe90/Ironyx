# Play Store listing — Ironyx

Draft copy. Character counts noted so it drops straight into Play Console.
Swap wording freely — the positioning (offline-first, private, no forced
account) is the one thing worth keeping, since it's the app's actual point
of difference in a saturated category.

**Status, 2026-09-20:** nothing here has been entered into Play Console or
App Store Connect yet (no developer account exists). Character counts were
re-measured today. Every factual claim in the copy is audited against the
current code in "Claims audit" at the bottom — re-run that audit before each
submission, and update the copy **in the same change** as any telemetry
decision (`TODO.md` D2). Store limits are from early-2026 knowledge; re-check
them against the live consoles.

## App name (30 char max)

```
Ironyx: Offline Workout Log
```
(27 characters)

## Short description (80 char max)

```
Log workouts, build programs, track progress. Fully offline. No account needed.
```
(79 characters)

## Full description (4000 char max)

```
Ironyx is a workout tracker built for the gym, not for the cloud.

No account required. No internet required. No subscription to see your
own numbers. Everything you log stays on your phone unless you
explicitly choose to back it up.

TRACK EVERY SET
Log exercises, sets, reps, and weight in seconds between sets. A built-in
rest timer with sound and haptics keeps you on pace without checking a
separate app.

BUILD REAL PROGRAMS
Create multi-day training programs and reuse them week after week, or
start from one of the built-in templates. Pick from a library of 300+
exercises, each with clear instructions.

SEE YOUR PROGRESS
Charts show volume, estimated one-rep max, and consistency over time —
not vanity stats, the numbers that tell you whether the program is
working.

PRIVATE BY DEFAULT
Your training log is not a product. Ironyx does not run ads or analytics,
and your local training log stays on your device unless you explicitly
enable cloud backup. Ironyx does not sell your data.

CLOUD BACKUP, ON YOUR TERMS
Create a free account only if you want an optional, one-tap backup —
useful before switching phones or reinstalling. It's off by default and
never uploads anything without you tapping "Back up now."

WORKS OFFLINE, ALWAYS
No signal at your gym? No problem. Every core feature — logging, timer,
programs, progress — works with zero connectivity, permanently, not just
when the servers are down.

Available in English and Arabic.

Questions or feedback: mustafa.salih15@gmail.com
```
(1,502 characters — well under the 4000 limit; room to add screenshots'
worth of detail later, e.g. specific program templates, once you have
user feedback on what to highlight)

Before submitting, consider adding one line the copy does not yet say:
*"You can delete your account and cloud backup from inside the app."* It is
true (Settings → Account → Delete account) and both stores look for it.

## ASO keywords to weave into the description / consider for the title

Primary (high intent, this app's actual strengths):
- workout log / workout tracker
- gym log
- offline workout app
- training log
- lifting tracker

Secondary (broader reach, more competition):
- fitness tracker
- exercise log
- strength training
- workout planner
- rep tracker

Avoid stuffing — Play's algorithm penalizes obvious keyword-stacking in
the short description more than it used to. One clean sentence beats five
crammed keywords.

## Feature graphic (1024×500) — content suggestion

Required by Play and **not yet made**. Copy angle for whoever makes it: the
navy-to-teal brand palette (`#0B1628` / `#38D6C0` — the icon's colours and,
since decision D3, the app's), the app icon plus 2-3 real screenshots
(dashboard, active workout logger, progress chart) angled slightly.

Tagline: the app's welcome screen says **"Your training, tracked."**
(`welcomeTagline`) — that is the only tested phrase. "Offline, private,
yours." is *new* copy; it matches the positioning but does not appear in
the app, so treat it as untested. (An earlier version of this note claimed
it was already in the welcome screen; it is not.)

## Screenshots — what to capture, in order

Play shows these in order, and most users don't scroll past the first
2-3, so lead with the differentiator, not the feature list:
1. Active workout / logger screen mid-set (the core loop)
2. Progress chart showing a trend line (proof the app produces insight,
   not just data entry)
3. Program builder or program detail (shows depth beyond a basic logger)
4. Settings → Data Management, framed to show local export/no-lock-in
   (reinforces the privacy angle visually, not just in text)
5. (optional) Dashboard
6. (optional) Exercise library

Capture these on a real device or emulator, in **light and dark** and in
**English and Arabic (RTL)** — both languages are in the listing, so the
Arabic set is in scope. Play needs at least 4 screenshots on some form
factors; check the current required sizes for each store **(verify)**.
Screenshots are `TODO.md` Week 2 ("Store assets round 1"). The
`test/golden/*.png` files are test renders, not store screenshots.

---

## Store metadata and declarations

| Field | Value | Notes |
|---|---|---|
| Category | Health & Fitness | Both stores (the earlier plan said "Sports") |
| Price | Free | Declare in-app purchases only when one exists; there is none |
| Ads | None | True today |
| Icon | PNG, no alpha **(verify)**, 512×512 (Play) / 1024×1024 (App Store) | Both `assets/branding/ironyx-icon-*.png` masters have transparent, pre-rounded corners (checked 2026-09-20) — flatten the 512 onto the navy gradient before uploading to Play. For the App Store use `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`, which was rebuilt opaque RGB |
| Feature graphic | 1024×500 | Required by Play; not made |
| Content rating | IARC questionnaire (Play) / age rating (Apple) | Not "PEGI 3" — Play rates via IARC |
| Contact | mustafa.salih15@gmail.com | Also the privacy-policy contact |
| Privacy policy URL | *not hosted yet* | Needed before **any** track goes live, closed testing included |
| Account-deletion URL | *not hosted yet* | Play needs a web URL in addition to the in-app path |

**Play Data Safety — what the binary actually does (2026-09-20).** Local
workout, body-metric and profile data never leave the device unless the user
taps "Back up now". With an account: email address and password (Supabase
Auth); with cloud backup: the whole training database as one gzipped
envelope (health and fitness information, plus profile fields such as date
of birth and height). Encrypted in transit (HTTPS/TLS). Deletable in-app
and by request. No data is sold or shared for advertising; no analytics,
ads or crash-reporting SDK is present **today** — that changes if D2 =
Sentry, and this section, the privacy policy and the listing copy must
change with it. Android Auto Backup is disabled (`allowBackup="false"`).
The health-apps declaration also applies.

**Exact-alarm permission declaration (Play).** The manifest declares
`USE_EXACT_ALARM` (plus `SCHEDULE_EXACT_ALARM` capped at Android 12L). Play
restricts this to apps whose core function is an alarm, timer or calendar —
justify it by the interval/rest timer, which fires phase-change alerts while
the app is backgrounded. If Play rejects it, delete both manifest lines and
the code falls back to inexact alarms (alerts can then arrive many seconds
late); nothing else changes. Reflected in `PRIVACY_POLICY.md`.

---

## iOS listing draft (only if `TODO.md` D1 = go)

Apple's name and subtitle limits are 30 characters each; the keyword field
is 100 **(verify)**. Apple does not want words repeated between name,
subtitle and keywords.

| Field | Draft | Length |
|---|---|---|
| Name | `Ironyx: Workout Log` | 19 |
| Subtitle | `Offline. Private. No account.` | 29 |
| Keywords | `gym,lifting,strength,training,tracker,routine,progress,1RM,program,rest timer,exercise,fitness` | 94 |

Reuse the Play full description. iOS needs its own screenshots at Apple's
current required sizes, a support URL, a privacy URL and the App Privacy
questionnaire (same answers as Data Safety above).

---

## Claims audit (checked against the code on 2026-09-20)

| Claim in the copy | Status |
|---|---|
| "No account required. No internet required." | True — auth is optional and everything core is local |
| "Pick from a library of 300+ exercises" | True — 301, seed v17 (the earlier plan said 150) |
| "A built-in rest timer **with sound** and haptics" | **Partly true.** Sound cues use the OS alert (`SystemSound.play`); no cue files are bundled (ADR-4 deviation). Fine on Android in practice; unverified on a device, and reportedly silent on iOS. Fix before iOS, or soften the copy |
| "Ironyx does not run ads or analytics" | True today (no such SDK in `pubspec.yaml`). **Breaks if D2 adds Sentry** — crash reporting is not "analytics", but the privacy policy currently says "no crash-reporting service" too |
| "Your local training log stays on your device unless you explicitly enable cloud backup" | True. Nothing uploads without tapping "Back up now" |
| "Charts show volume, estimated one-rep max, and consistency" | True — Progress phases 0–4 shipped |
| "Available in English and Arabic" | True |
| "Every core feature … works with zero connectivity, permanently" | True for the app's own features; sign-in and backup need a network |
| "sync later", "open APIs", "60fps / minimal battery drain", "Free with IAP" (from the 12-week plan's source) | **Do not use** — no sync, no API, unmeasured performance, no IAP (`TODO.md` C6) |
