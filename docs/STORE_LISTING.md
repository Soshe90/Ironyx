# Play Store listing — Ironyx

Draft copy. Character counts noted so it drops straight into Play Console.
Swap wording freely — the positioning (offline-first, private, no forced
account) is the one thing worth keeping, since it's the app's actual point
of difference in a saturated category.

**Status, 2026-09-21:** nothing here has been entered into Play Console or
App Store Connect yet (no developer account exists). Character counts were
re-measured 2026-09-20 and the description again after the deletion sentence
was added. The Play Console answer table below is drafted; the screenshots
and feature graphic are not made yet (`TODO.md` S1, S2). Every factual claim in the copy is audited against the
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

**English**

```
Log every set, follow your training plan, and see your progress — offline.
```
(74 characters)

**Arabic**

```
سجّل تمارينك، تابع خطتك، واكتشف تقدمك — حتى دون اتصال بالإنترنت.
```

## Full description (4000 char max)

### English

```
Make every workout count with Ironyx, a workout tracker that keeps your training log on your device and works offline.

LOG YOUR WORKOUTS
Record exercises, sets, reps, and weights as you train. Check your workout history whenever you need it, and use the built-in rest timer to stay focused between sets.

PLAN YOUR TRAINING
Create multi-day programs, reuse your routines, or start with a built-in template. Explore a library of more than 300 exercises with instructions to help you get started.

SEE HOW YOU’RE PROGRESSING
Follow your training over time with charts for workout volume, estimated one-rep max, and consistency. Your history helps you see the work behind your progress.

YOUR TRAINING, YOUR CHOICE
No account is needed to use the core workout tracker. Your workouts are stored on your device, and Ironyx does not show ads or use analytics. If you choose to create an account, you can manually back up your data to the cloud. Nothing is backed up until you choose “Back up now.”

TRAIN OFFLINE
No internet at the gym? Keep logging workouts, using your programs and timer, and viewing your progress offline.

Available in English and Arabic.

Questions or feedback: mustafa.salih15@gmail.com
```

### Arabic

```
اجعل لكل تمرين قيمة مع Ironyx، تطبيق يساعدك على تسجيل تدريباتك ومتابعة تقدمك، مع حفظ سجلّك على جهازك وإمكانية استخدام الميزات الأساسية دون إنترنت.

سجّل تمارينك
دوّن التمارين والمجموعات والتكرارات والأوزان أثناء التدريب، وارجع إلى سجل تمارينك متى احتجت. استخدم مؤقّت الراحة المدمج لتنظيم فترات الراحة بين المجموعات.

خطّط لتدريبك
أنشئ برامج تدريبية متعددة الأيام وأعد استخدام خططك، أو ابدأ بأحد القوالب الجاهزة. استكشف مكتبة تضم أكثر من 300 تمرين مع إرشادات تساعدك على البدء.

تابع تقدمك
استخدم الرسوم البيانية لمتابعة حجم التدريب، والقوة التقديرية لتكرار واحد، وانتظامك في التمرين بمرور الوقت. راجع سجلّك لترى كيف يتراكم جهدك.

تدريبك وبياناتك تحت اختيارك
لا تحتاج إلى حساب لاستخدام الميزات الأساسية. تُحفظ تمارينك على جهازك، ولا يعرض Ironyx إعلانات ولا يستخدم أدوات التحليلات. إذا رغبت، يمكنك إنشاء حساب وعمل نسخة احتياطية من بياناتك على السحابة يدويًا. لا تُرفع بياناتك حتى تختار «النسخ الاحتياطي الآن».

تدرّب دون إنترنت
لا يوجد اتصال بالإنترنت في النادي؟ واصل تسجيل تمارينك واستخدام برامجك والمؤقّت والاطلاع على تقدمك دون اتصال.

متوفر باللغتين العربية والإنجليزية.

للاستفسارات أو الملاحظات: mustafa.salih15@gmail.com
```

The descriptions intentionally do not promise in-app account deletion. Add that claim only after the real Supabase account-deletion flow has been verified end to end (`TODO.md` C4).

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
| Icon | PNG, no alpha **(verify)**, 512×512 (Play) / 1024×1024 (App Store) | Both `assets/branding/ironyx-icon-512.png` and `-1024.png` masters have transparent, pre-rounded corners (checked 2026-09-20), so **don't upload them**. Use `assets/branding/ironyx-icon-512-opaque.png` for Play (512×512 RGB, no alpha, downscaled from the iOS icon; added 2026-09-20) and `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` for the App Store (1024×1024 RGB) |
| Feature graphic | 1024×500 | Required by Play; not made |
| Content rating | IARC questionnaire (Play) / age rating (Apple) | Not "PEGI 3" — Play rates via IARC |
| Contact | mustafa.salih15@gmail.com | Also the privacy-policy contact |
| Privacy policy URL | `https://soshe90.github.io/Ironyx/privacy/` | Needed before **any** track goes live, closed testing included. **Not live until** the commit is pushed and GitHub Pages is switched on (`TODO.md` C2); open it in a browser before pasting |
| Account-deletion URL | `https://soshe90.github.io/Ironyx/delete-account/` | Play needs a web URL in addition to the in-app path. Same Pages prerequisite |

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

### Play Console answers, form by form (`TODO.md` S3)

Written 2026-09-21 from the code and the policy pages, **not** from the live
console: Play renames and reorders these forms, so where the wording below is
a category name or option label it is marked *(verify)*. Do not tick a box the
build does not support just because a row here says so.

| Play Console form | Answer |
|---|---|
| App details | Name `Ironyx: Offline Workout Log`; **App**, **Free**; category **Health & Fitness**; contact `mustafa.salih15@gmail.com` |
| Store listing | Short and full description from above; icon `assets/branding/ironyx-icon-512-opaque.png`; feature graphic (S2); the screenshots (S1) |
| App access | **All functionality is available without special access.** Accounts are optional and unlock only cloud backup, so no test login is needed |
| Ads | **No**, the app contains no ads |
| Content rating (IARC) | Category: utility/productivity/other *(verify)*. Answer **No** to violence, sexual content, profanity, controlled substances, gambling, and user-generated content shared between users; no location sharing; no digital purchases. Expect an "Everyone"-level rating |
| Target audience | **18 and over** only, which avoids the Families-policy obligations. If you deliberately want younger teens, that is a separate decision: the policy says "not directed at children under 13" |
| News app / COVID-19 / government | **No** to each |
| Data safety: collection | **Yes**, the app collects data, but only if the user opts in. Never collected without an account |
| Data safety: types | Email address (*Personal info*) and the password used to sign in (*Personal info / authentication* *(verify)*); *Health info* and *Fitness info*, because a cloud backup contains workouts, body metrics, date of birth, sex and height |
| Data safety: per type | **Collected**, not shared (Supabase acts as a service provider on our behalf *(verify Play's "service provider" wording)*). **Optional**, not required. Purposes: *App functionality* and *Account management*. Not used for analytics, advertising or personalisation |
| Data safety: practices | **Encrypted in transit: yes** (HTTPS/TLS). **Users can request deletion: yes**, in-app (Settings → Account → Delete account) and by the deletion URL above. Data is not sold. No independent security review to declare |
| Health apps declaration | Features: activity and fitness tracking (manual logging only). Does **not** use Health Connect or any health platform, and is not a medical device (the policy says so). Complete the form as the "fitness / activity tracking" type *(verify)* |
| Advertising ID | **No** — the app does not use it and no SDK reads it |
| Government / financial / SMS / call-log / VPN / accessibility declarations | **None apply** |
| Exact alarms | Permission `USE_EXACT_ALARM`. Core function: the interval and rest timer fires phase-change and completion alerts at the exact second while the app is in the background or the screen is locked. Delayed delivery would make the timer useless for training. Used only for timers the user starts |
| Privacy policy / deletion URLs | The two URLs in the metadata table above |

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
| "A built-in rest timer **with sound** and haptics" | **True on Android** as of 2026-09-20: three bundled cues (countdown, phase change, completion) play through `just_audio`, ducking other audio — confirmed in logcat on an Android 15 emulator's release build. Not yet heard on a physical device, and not checked on iOS at all. Re-verify both before claiming it for iOS |
| "Ironyx does not run ads or analytics" | True today (no such SDK in `pubspec.yaml`). **Breaks if D2 adds Sentry** — crash reporting is not "analytics", but the privacy policy currently says "no crash-reporting service" too |
| "Your local training log stays on your device unless you explicitly enable cloud backup" | True. Nothing uploads without tapping "Back up now" |
| "Charts show volume, estimated one-rep max, and consistency" | True — Progress phases 0–4 shipped |
| "Available in English and Arabic" | True |
| "Every core feature … works with zero connectivity, permanently" | True for the app's own features; sign-in and backup need a network |
| "sync later", "open APIs", "60fps / minimal battery drain", "Free with IAP" (from the 12-week plan's source) | **Do not use** — no sync, no API, unmeasured performance, no IAP (`TODO.md` C6) |
